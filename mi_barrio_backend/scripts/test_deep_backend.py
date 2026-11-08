"""Pruebas profundas del backend: casos raros, datos inválidos y ataques comunes.

Uso (con la API levantada):
    venv\\Scripts\\python.exe scripts\\test_deep_backend.py http://127.0.0.1:8000

Crea barrios aislados (no toca BARRIO-01). Revisa que el servidor:
- rechace tokens falsos, alterados o de otro rol,
- no deje leer ni escribir en otro barrio,
- valide los datos (largos, coordenadas, UUID, JSON roto) sin caerse (nunca 500),
- trate los textos con SQL o HTML como texto normal.
"""
import base64
import json
import sys
import urllib.error
import urllib.request

from _test_env import http, isolated_neighborhood, register

BASE = (sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8000").rstrip("/")
failures = 0
total = 0


def check(name: str, ok: bool, detail=None) -> None:
    global failures, total
    total += 1
    print(("OK   " if ok else "FALLA") + " " + name + ("" if ok else f"  -> {str(detail)[:200]}"))
    if not ok:
        failures += 1


def raw(method: str, path: str, data: bytes, headers: dict) -> int:
    """Envía bytes tal cual (para JSON roto) y devuelve el código HTTP."""
    req = urllib.request.Request(BASE + path, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status
    except urllib.error.HTTPError as e:
        return e.code


def tamper(token: str, **changes) -> str:
    """Cambia el contenido del token sin volver a firmarlo."""
    header, payload, signature = token.split(".")
    padded = payload + "=" * (-len(payload) % 4)
    claims = json.loads(base64.urlsafe_b64decode(padded))
    claims.update(changes)
    new_payload = base64.urlsafe_b64encode(json.dumps(claims).encode()).decode().rstrip("=")
    return f"{header}.{new_payload}.{signature}"


def main() -> int:
    hood = isolated_neighborhood(BASE, "Pruebas profundas")
    other = isolated_neighborhood(BASE, "Otro barrio profundo")
    tenant = hood["tenant_id"]
    me = register(BASE, hood["join_code"], "VECINO", "Vecina Profunda")
    stranger = register(BASE, other["join_code"], "VECINO", "Vecino de otro barrio")
    lat, lng = -5.1945, -80.6328

    def call(method, path, body=None, token=None, tenant_id=None):
        return http(BASE, method, path, body, tenant=tenant_id or tenant, token=token or me["token"])

    # ── 1. Tokens ──
    s, _ = call("GET", "/api/v1/services", token="no.es.un-token")
    check("token basura -> 401", s == 401, s)
    s, _ = call("GET", "/api/v1/services", token=tamper(me["token"], role="ADMIN_BARRIO"))
    check("token con rol cambiado (firma rota) -> 401", s == 401, s)
    s, _ = call("GET", "/api/v1/services", token=tamper(me["token"], exp=1))
    check("token vencido o alterado -> 401", s == 401, s)
    s, _ = call("PATCH", "/api/v1/tenants/emergency-toggle", {"is_emergency_active": True})
    check("un vecino no activa la emergencia -> 403", s == 403, s)

    # ── 2. Aislamiento entre barrios ──
    s, _ = call("GET", "/api/v1/services", tenant_id=other["tenant_id"])
    check("mi token no lee otro barrio -> 403", s == 403, s)
    s, post = call("POST", "/api/v1/solidarity", {
        "author_user_id": me["id"], "flow_type": "SOLICITO_AYUDA",
        "modality": "PRESTAMO_HERRAMIENTA", "title": "Escalera", "lat": lat, "lng": lng})
    check("publicar en mi barrio -> 201", s == 201, f"{s} {post}")
    pid = post.get("id") if isinstance(post, dict) else "x"
    s, _ = http(BASE, "GET", f"/api/v1/solidarity/{pid}", tenant=other["tenant_id"],
                token=stranger["token"])
    check("otro barrio no ve mi publicación -> 404", s in (403, 404), s)
    s, _ = http(BASE, "DELETE", f"/api/v1/solidarity/{pid}", tenant=other["tenant_id"],
                token=stranger["token"])
    check("otro barrio no borra mi publicación", s in (403, 404), s)
    s, _ = call("POST", "/api/v1/solidarity", {
        "author_user_id": stranger["id"], "flow_type": "SOLICITO_AYUDA",
        "modality": "PRESTAMO_HERRAMIENTA", "title": "Suplantar", "lat": lat, "lng": lng})
    check("publicar a nombre de otro -> 403", s == 403, s)

    # ── 3. Validación de datos (nunca 500) ──
    s, _ = call("POST", "/api/v1/solidarity", {
        "author_user_id": me["id"], "flow_type": "SOLICITO_AYUDA",
        "modality": "PRESTAMO_HERRAMIENTA", "title": "x" * 5000, "lat": lat, "lng": lng})
    check("título gigante -> 422", s == 422, s)
    s, _ = call("POST", "/api/v1/solidarity", {
        "author_user_id": me["id"], "flow_type": "SOLICITO_AYUDA",
        "modality": "PRESTAMO_HERRAMIENTA", "title": "Coordenadas", "lat": 999, "lng": lng})
    check("latitud imposible -> 422", s == 422, s)
    s, _ = call("POST", "/api/v1/solidarity", {
        "author_user_id": me["id"], "flow_type": "INVENTADO",
        "modality": "PRESTAMO_HERRAMIENTA", "title": "Tipo", "lat": lat, "lng": lng})
    check("tipo de publicación inventado -> 422", s == 422, s)
    s, _ = call("GET", "/api/v1/solidarity/no-es-uuid")
    check("id que no es UUID -> 422 (no 500)", s == 422, s)
    s = raw("POST", "/api/v1/auth/login", b'{"email": "a@b.com", "password":',
            {"Content-Type": "application/json"})
    check("JSON roto -> 422 (no 500)", s == 422, s)
    s, _ = http(BASE, "POST", "/api/v1/auth/register", {
        "full_name": "A", "email": "no-es-correo", "password": "corta",
        "role": "VECINO", "join_code": hood["join_code"]})
    check("registro con datos inválidos -> 422", s == 422, s)
    s, _ = http(BASE, "POST", "/api/v1/auth/register", {
        "full_name": "Rol Falso", "email": "rolfalso@pruebas.test", "password": "Clave12345",
        "role": "ADMIN_BARRIO", "join_code": hood["join_code"]})
    check("nadie se registra como admin del barrio", s in (403, 422), s)

    # ── 4. Textos peligrosos se guardan como texto ──
    evil = "'; DROP TABLE users; -- <script>alert(1)</script>"
    s, evil_post = call("POST", "/api/v1/solidarity", {
        "author_user_id": me["id"], "flow_type": "SOLICITO_AYUDA",
        "modality": "PRESTAMO_HERRAMIENTA", "title": evil[:150], "lat": lat, "lng": lng})
    check("texto con SQL/HTML se acepta como texto", s == 201, s)
    s, back = call("GET", f"/api/v1/solidarity/{evil_post.get('id') if isinstance(evil_post, dict) else 'x'}")
    check("y vuelve igual, sin ejecutarse", s == 200 and back.get("title") == evil[:150], back)
    s, _ = http(BASE, "POST", "/api/v1/auth/login",
                {"email": "' OR '1'='1", "password": "' OR '1'='1"})
    check("inyección SQL en el login no entra", s in (401, 422), s)
    s, _ = call("GET", "/api/v1/services")
    check("la tabla de usuarios sigue viva (mi sesión funciona)", s == 200, s)

    # ── 5. Rutas públicas y salud ──
    s, health = http(BASE, "GET", "/health/live")
    check("/health/live responde sin sesión", s == 200, s)
    s, _ = http(BASE, "GET", "/api/v1/services")
    check("ruta privada sin sesión -> 401 o 400", s in (400, 401), s)

    # ── 6. SOS sin señal con "¿Hay heridos?" sin responder (null) ──
    import uuid
    from datetime import datetime, timezone
    sos_id = str(uuid.uuid4())
    s, r = call("POST", "/api/v1/sync/push", {
        "client_sync_timestamp": datetime.now(timezone.utc).isoformat(),
        "mutations": [{"target_table": "vulnerable_reports", "record_id": sos_id, "operation": "UPSERT",
                       "payload": {"id": sos_id, "reporter_user_id": me["id"], "urgency_level": "CRITICA",
                                   "vulnerability_type": "ATENCION_MEDICA", "status": "PENDIENTE_APOYO",
                                   "description": "Necesito ayuda", "lat": lat, "lng": lng,
                                   "has_injured": None, "is_deleted": False,
                                   "updated_at": datetime.now(timezone.utc).isoformat()}}]})
    check("SOS sin responder '¿hay heridos?' se guarda (no queda trabado)",
          s == 200 and r["processed_record_ids"] == [sos_id], r)

    print(f"\n{total - failures}/{total} pruebas OK")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
