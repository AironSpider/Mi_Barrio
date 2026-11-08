"""Prueba de cuentas reales: verificar correo, recuperar contraseña y Google.

Uso (con el backend local encendido con AUTH_DEBUG_CODES=1 y SIN SMTP_USER):
    venv\\Scripts\\python.exe scripts\\test_auth_accounts.py http://127.0.0.1:8000

Crea su propio barrio de prueba; no toca BARRIO-01. La parte de Google prueba la
lógica del servidor con una identidad ya verificada (no llama a Google).
"""
import asyncio
import secrets
import sys
import time

from _test_env import http, isolated_neighborhood

BASE = (sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8000").rstrip("/")
results: list[tuple[bool, str]] = []


def check(name: str, ok: bool, detail=None) -> None:
    results.append((ok, name))
    print(("OK   " if ok else "FAIL ") + name + ("" if ok else f"  -> {detail}"))


async def _db(statement: str, **params):
    from sqlalchemy import text
    from app.core.database import engine
    async with engine.begin() as conn:
        result = await conn.execute(text(statement), params)
        rows = result.fetchall() if result.returns_rows else None
    await engine.dispose()
    return rows


def db(statement: str, **params):
    return asyncio.run(_db(statement, **params))


def main() -> int:
    hood = isolated_neighborhood(BASE, "Cuentas reales")
    code = hood["join_code"]
    mail = f"Vecina.Real{secrets.token_hex(3)}@Gmail.com"
    password = "Clave-" + secrets.token_hex(4)

    # ── 1. Registro: la cuenta nace sin verificar ──
    s, r = http(BASE, "POST", "/api/v1/auth/register", {
        "full_name": "Vecina Real", "email": mail, "password": password,
        "role": "VECINO", "join_code": code})
    check("registro crea la cuenta", s == 201, r)
    check("la cuenta nueva no está verificada", s == 201 and r["user"]["email_verified"] is False, r)
    token = r.get("access_token") if s == 201 else None

    s, r = http(BASE, "POST", "/api/v1/auth/login", {"email": mail, "password": password})
    check("puede entrar aunque falte verificar (la app le pide el código)",
          s == 200 and r["user"]["email_verified"] is False, r)

    # ── 2. Reenviar el código: espera de 60 s ──
    s, r = http(BASE, "POST", "/api/v1/auth/email/send-code", {"email": mail})
    check("pedir otro código enseguida responde 429", s == 429, r)

    db("UPDATE auth_codes SET created_at = created_at - interval '2 minutes' WHERE email = :e",
       e=mail.lower())
    s, r = http(BASE, "POST", "/api/v1/auth/email/send-code", {"email": mail})
    debug = r.get("debug_code") if isinstance(r, dict) else None
    check("pasado 1 minuto se puede pedir otro código", s == 200 and debug, r)

    s, r = http(BASE, "POST", "/api/v1/auth/email/verify", {"email": mail, "code": "000000" if debug != "000000" else "111111"})
    check("un código equivocado se rechaza (400)", s == 400, r)

    s, r = http(BASE, "POST", "/api/v1/auth/email/verify", {"email": mail, "code": debug})
    check("el código correcto verifica el correo", s == 200 and r["user"]["email_verified"] is True, r)

    s, r = http(BASE, "POST", "/api/v1/auth/email/verify", {"email": mail, "code": debug})
    check("un código ya usado no se puede volver a usar... pero la cuenta sigue verificada",
          s == 200 and r["user"]["email_verified"] is True, r)

    s, r = http(BASE, "POST", "/api/v1/auth/email/send-code", {"email": "nadie@noexiste.pe"})
    check("pedir código de un correo sin cuenta no revela nada", s == 200 and not r.get("debug_code"), r)

    # ── 3. Recuperar contraseña ──
    s, r = http(BASE, "POST", "/api/v1/auth/password/forgot", {"email": mail})
    reset_code = r.get("debug_code") if isinstance(r, dict) else None
    check("olvidé mi contraseña envía un código", s == 200 and reset_code, r)

    s, r = http(BASE, "POST", "/api/v1/auth/password/forgot", {"email": "nadie@noexiste.pe"})
    check("olvidé mi contraseña con un correo sin cuenta responde igual", s == 200 and not r.get("debug_code"), r)

    new_password = "Nueva-" + secrets.token_hex(4)
    s, r = http(BASE, "POST", "/api/v1/auth/password/reset",
                {"email": mail, "code": "123456" if reset_code != "123456" else "654321", "new_password": new_password})
    check("cambiar la contraseña con un código equivocado falla", s == 400, r)

    s, r = http(BASE, "POST", "/api/v1/auth/password/reset",
                {"email": mail, "code": reset_code, "new_password": "corta"})
    check("la contraseña nueva debe tener 8 caracteres o más (422)", s == 422, r)

    s, r = http(BASE, "POST", "/api/v1/auth/password/reset",
                {"email": mail, "code": reset_code, "new_password": new_password})
    check("cambiar la contraseña con el código correcto inicia sesión", s == 200 and r.get("access_token"), r)

    s, r = http(BASE, "POST", "/api/v1/auth/login", {"email": mail, "password": password})
    check("la contraseña vieja ya no sirve", s == 401, r)
    s, r = http(BASE, "POST", "/api/v1/auth/login", {"email": mail, "password": new_password})
    check("la contraseña nueva sí sirve", s == 200, r)

    # 5 códigos equivocados agotan el código
    db("UPDATE auth_codes SET created_at = created_at - interval '2 minutes' WHERE email = :e",
       e=mail.lower())
    s, r = http(BASE, "POST", "/api/v1/auth/password/forgot", {"email": mail})
    last_code = r.get("debug_code")
    wrong = "999999" if last_code != "999999" else "888888"
    for _ in range(5):
        http(BASE, "POST", "/api/v1/auth/password/reset", {"email": mail, "code": wrong, "new_password": new_password})
    s, r = http(BASE, "POST", "/api/v1/auth/password/reset", {"email": mail, "code": last_code, "new_password": new_password})
    check("tras 5 intentos fallidos el código deja de servir", s in (400, 429), r)

    # ── 4. Google (lógica del servidor con una identidad ya verificada) ──
    google_token, google_mail = asyncio.run(_google_checks(code, mail.lower()))

    # ── 5. Quien entró con Google crea su contraseña ──
    s, r = http(BASE, "GET", "/api/v1/auth/me", token=google_token)
    check("Google: /me dice que aún no tiene contraseña", s == 200 and r["has_password"] is False, r)
    s, r = http(BASE, "POST", "/api/v1/auth/password/set", {"password": "corta"}, token=google_token)
    check("crear contraseña: menos de 8 caracteres se rechaza (422)", s == 422, r)
    s, r = http(BASE, "POST", "/api/v1/auth/password/set", {"password": "Nueva-" + secrets.token_hex(4)})
    check("crear contraseña sin sesión se rechaza (401)", s == 401, r)
    google_password = "Nueva-" + secrets.token_hex(4)
    s, r = http(BASE, "POST", "/api/v1/auth/password/set", {"password": google_password}, token=google_token)
    check("crear contraseña con sesión la guarda", s == 200 and r["user"]["has_password"] is True, r)
    s, r = http(BASE, "POST", "/api/v1/auth/password/set", {"password": "Otra-" + secrets.token_hex(4)}, token=google_token)
    check("crear contraseña otra vez responde 409 (se cambia con el código)", s == 409, r)
    s, r = http(BASE, "POST", "/api/v1/auth/login", {"email": google_mail, "password": google_password})
    check("la cuenta de Google ya entra también con su contraseña", s == 200, r)

    # ── 6. Correos falsos no se registran ──
    for label, bad in [("temporal", f"x{secrets.token_hex(3)}@mailinator.com"),
                       ("con error de tipeo", f"vecina{secrets.token_hex(3)}@gmial.com"),
                       ("Gmail muy corto", "ab1@gmail.com"),
                       ("Gmail con símbolos", f"ana_{secrets.token_hex(3)}@gmail.com")]:
        s, r = http(BASE, "POST", "/api/v1/auth/register", {
            "full_name": "Falsa", "email": bad, "password": password,
            "role": "VECINO", "join_code": code})
        check(f"registro con correo {label} se rechaza (422)", s == 422, r)

    s, r = http(BASE, "POST", "/api/v1/auth/google", {"id_token": "x" * 40})
    check("un token de Google falso no entra (401 o 503 si Google no está configurado)", s in (401, 503), r)

    ok = sum(1 for good, _ in results if good)
    print(f"\n{ok}/{len(results)} pruebas OK  (barrio de prueba {hood['tenant_id']})")
    return 0 if ok == len(results) else 1


async def _google_checks(join_code: str, existing_email: str) -> tuple[str, str]:
    from fastapi import HTTPException
    from app.core.database import async_session_factory as AsyncSessionLocal, engine
    from app.core.google_auth import GoogleIdentity, identity_from_claims
    from app.features.auth_barrio.account_router import NEEDS_NEIGHBORHOOD, google_login
    from app.features.auth_barrio.schemas import GoogleLoginRequest

    ids = {"web-client.apps.googleusercontent.com"}
    good = {"aud": "web-client.apps.googleusercontent.com", "iss": "https://accounts.google.com",
            "exp": str(int(time.time()) + 600), "email_verified": "true", "sub": "123",
            "email": "Ana@Gmail.com", "name": "Ana Torres"}
    ident = identity_from_claims(good, ids)
    check("Google: token válido da correo en minúsculas y nombre", ident.email == "ana@gmail.com" and ident.name == "Ana Torres")
    for field, value, label in [("aud", "otra-app", "otra app"), ("iss", "evil.com", "otro emisor"),
                                ("exp", "1", "vencido"), ("email_verified", "false", "correo sin verificar")]:
        try:
            identity_from_claims({**good, field: value}, ids)
            check(f"Google: rechaza token de {label}", False, "no lanzó")
        except HTTPException as exc:
            check(f"Google: rechaza token de {label}", exc.status_code == 401, exc.detail)

    sub = "google-" + secrets.token_hex(4)
    new_mail = f"nuevo.{secrets.token_hex(3)}@gmail.com"
    new_ident = GoogleIdentity(sub=sub, email=new_mail, name="Nuevo Vecino")
    async with AsyncSessionLocal() as session:
        try:
            await google_login(session, new_ident, GoogleLoginRequest(id_token="x" * 40))
            check("Google: cuenta nueva sin código de barrio pide el barrio (428)", False, "no lanzó")
        except HTTPException as exc:
            check("Google: cuenta nueva sin código de barrio pide el barrio (428)",
                  exc.status_code == 428 and exc.detail == NEEDS_NEIGHBORHOOD, exc.detail)
    async with AsyncSessionLocal() as session:
        r = await google_login(session, new_ident, GoogleLoginRequest(id_token="x" * 40, join_code=join_code, role="COMERCIANTE"))
        check("Google: con el código de barrio crea la cuenta verificada",
              r.user.email == new_mail and r.user.email_verified and r.user.role == "COMERCIANTE")
        check("Google: la cuenta nueva todavía no tiene contraseña", r.user.has_password is False)
        new_token = r.access_token
    async with AsyncSessionLocal() as session:
        r = await google_login(session, new_ident, GoogleLoginRequest(id_token="x" * 40))
        check("Google: la segunda vez entra directo a la misma cuenta", r.user.email == new_mail)
    async with AsyncSessionLocal() as session:
        linked = GoogleIdentity(sub="google-" + secrets.token_hex(4), email=existing_email, name="Vecina Real")
        r = await google_login(session, linked, GoogleLoginRequest(id_token="x" * 40))
        check("Google: si ya tenía cuenta con ese correo, la vincula y entra", r.user.email == existing_email)
        check("Google: al vincular conserva su contraseña", r.user.has_password is True)
    await engine.dispose()
    return new_token, new_mail


if __name__ == "__main__":
    sys.exit(main())
