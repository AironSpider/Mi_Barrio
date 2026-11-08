"""Prueba de "Borrar mi cuenta" (DELETE /api/v1/users/me) contra el backend levantado.

Uso:  venv\\Scripts\\python.exe scripts\\test_delete_account.py http://127.0.0.1:8000
Crea un barrio aislado (no toca BARRIO-01).
"""
import sys

from _test_env import http, isolated_neighborhood, register

BASE = (sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8000").rstrip("/")
failures = 0


def check(name: str, ok: bool, detail=None) -> None:
    global failures
    print(("OK   " if ok else "FALLA") + " " + name + ("" if ok else f"  -> {detail}"))
    if not ok:
        failures += 1


def main() -> int:
    hood = isolated_neighborhood(BASE, "Borrar cuenta")
    tenant, code = hood["tenant_id"], hood["join_code"]
    me = register(BASE, code, "VECINO", "Rosa Calle Prueba")
    other = register(BASE, code, "VECINO", "Otro Vecino")

    def call(method, path, body=None, token=None):
        return http(BASE, method, path, body, tenant=tenant, token=token or me["token"])

    s, post = call("POST", "/api/v1/solidarity", {
        "author_user_id": me["id"], "flow_type": "SOLICITO_AYUDA",
        "modality": "PRESTAMO_HERRAMIENTA", "title": "Préstamo de escalera",
        "lat": -5.1945, "lng": -80.6328})
    check("publica antes de borrar", s == 201, f"{s} {post}")
    pid = post.get("id") if isinstance(post, dict) else None

    s, _ = http(BASE, "DELETE", "/api/v1/users/me", tenant=tenant)
    check("sin sesión -> 401", s == 401, s)

    s, b = http(BASE, "DELETE", "/api/v1/users/me", tenant=tenant, token=hood["admin_token"])
    check("admin del barrio -> 403", s == 403, f"{s} {b}")

    s, b = call("DELETE", "/api/v1/users/me")
    check("borrar mi cuenta -> 200", s == 200 and b.get("deleted") is True, f"{s} {b}")

    s, _ = call("GET", "/api/v1/users/me")
    check("el token ya no sirve", s in (401, 403, 404), s)

    s, _ = http(BASE, "POST", "/api/v1/auth/login",
                {"email": me["email"], "password": me["password"]})
    check("ya no puede iniciar sesión", s == 401, s)

    s, posts = call("GET", "/api/v1/solidarity", token=other["token"])
    check("su publicación ya no se ve", s == 200 and all(p["id"] != pid for p in posts), s)

    s, b = call("DELETE", "/api/v1/users/me")
    check("borrar dos veces no rompe", s in (401, 403, 404), f"{s} {b}")

    s, r = http(BASE, "POST", "/api/v1/auth/register", {
        "full_name": "Rosa Nueva", "email": me["email"], "password": "Nueva1234x",
        "role": "VECINO", "join_code": code})
    check("el correo queda libre para otra cuenta", s == 201, f"{s} {r}")

    print(f"\n{'TODO OK' if not failures else f'{failures} FALLAS'}")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
