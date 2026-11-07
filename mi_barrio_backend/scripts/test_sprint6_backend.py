"""Pruebas del backend del Sprint 6 contra el servidor levantado.

Uso (con uvicorn corriendo):
    venv\\Scripts\\python.exe scripts\\test_sprint6_backend.py [http://localhost:8000]

Cubre:
- Pull por `server_updated_at`: un post creado offline HORAS antes y subido
  después del último pull SÍ llega (el bug que rompía la demo con 2 celulares).
- El pull trae `tenant` (Modo Emergencia del barrio) y `vulnerable_reports`.
- `GET /api/v1/tenants/current` y `PATCH /api/v1/tenants/emergency-toggle`.
- El celular no puede escribir `server_updated_at`.

Requiere migraciones aplicadas y MI_BARRIO_JWT_SECRET configurada. Crea una cuenta
y datos de prueba en el barrio demo; úsalo únicamente con una base de desarrollo.
El toggle de emergencia se restaura al estado original.
"""
import json
import sys
import time
import urllib.error
import urllib.request
import uuid
from datetime import datetime, timedelta, timezone

# La consola de Windows no siempre usa UTF-8: evita que un acento o "→" rompa el script.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

BASE = (sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8000").rstrip("/")
DEMO = "a1b2c3d4-e5f6-4a8b-9c0d-1e2f3a4b5c6d"
T = DEMO
ME = ""
ACCESS_TOKEN = ""
LAT, LNG = -5.1945, -80.6328

results: list[tuple[bool, str, str]] = []


def call(
    method: str,
    path: str,
    body=None,
    tenant: str | None = T,
    *,
    authenticated: bool = True,
):
    headers = {"Content-Type": "application/json"}
    if tenant:
        headers["X-Tenant-ID"] = tenant
    if authenticated and ACCESS_TOKEN:
        headers["Authorization"] = "Bearer " + ACCESS_TOKEN
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(BASE + path, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            text = r.read().decode()
            return r.status, (json.loads(text) if text else None)
    except urllib.error.HTTPError as e:
        text = e.read().decode()
        try:
            return e.code, json.loads(text)
        except ValueError:
            return e.code, text[:200]


def check(name: str, ok: bool, detail="") -> bool:
    results.append((bool(ok), name, "" if ok else str(detail)[:300]))
    return bool(ok)


def iso(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def post_mutation(post_id: str, title: str, client_time: datetime) -> dict:
    return {
        "target_table": "solidarity_posts",
        "record_id": post_id,
        "operation": "UPSERT",
        "payload": {
            "id": post_id, "author_user_id": ME, "flow_type": "SOLICITO_AYUDA",
            "modality": "PRESTAMO_HERRAMIENTA", "title": title, "description": None,
            "is_emergency_context": False, "status": "DISPONIBLE", "lat": LAT, "lng": LNG,
            "is_deleted": False, "updated_at": iso(client_time),
            "server_updated_at": "2000-01-01T00:00:00Z",  # intento de falsificar: debe ignorarse
        },
    }


def push(*mutations) -> tuple[int, dict]:
    return call("POST", "/api/v1/sync/push", {
        "client_sync_timestamp": iso(datetime.now(timezone.utc)), "mutations": list(mutations)})


def main() -> int:
    global ACCESS_TOKEN, ME
    s, h = call("GET", "/health", tenant=None)
    if s != 200:
        print(f"Backend no disponible en {BASE} (HTTP {s}). Levanta uvicorn primero.")
        return 2
    check("health: migraciones al día", h["data"].get("migrations_up_to_date") is True, h)

    email = f"auth-test-{uuid.uuid4()}@example.test"
    password = "MiBarrio-test-123"
    s, registered = call(
        "POST",
        "/api/v1/auth/register",
        {
            "full_name": "Usuario de prueba",
            "email": email,
            "password": password,
            "role": "VECINO",
            "join_code": "BARRIO-01",
        },
        tenant=None,
        authenticated=False,
    )
    check("registro devuelve usuario, barrio y token", s == 201 and registered.get("access_token"), registered)
    if s != 201 or not registered.get("access_token"):
        print("No se pudo crear la cuenta de prueba; revisa migraciones, secreto y código del barrio.")
        return 2
    ACCESS_TOKEN = registered["access_token"]
    ME = registered["user"]["id"]

    s, logged_in = call(
        "POST",
        "/api/v1/auth/login",
        {"email": email, "password": password},
        tenant=None,
        authenticated=False,
    )
    check("login devuelve token Bearer", s == 200 and logged_in.get("access_token"), logged_in)
    s, current = call("GET", "/api/v1/auth/me", tenant=None)
    check("GET /auth/me valida la sesión", s == 200 and current.get("id") == ME, current)
    s, unauthenticated = call(
        "GET", "/api/v1/sync/pull", tenant=T, authenticated=False
    )
    check("API protegida rechaza solicitudes sin token", s == 401, unauthenticated)
    s, wrong_tenant = call("GET", "/api/v1/sync/pull", tenant=str(uuid.uuid4()))
    check("el token no permite acceder a otro barrio", s == 403, wrong_tenant)

    # ── 1. Escenario de la demo con 2 celulares ──
    # Celular B sincroniza (cursor C1).
    s, first = call("GET", "/api/v1/sync/pull")
    check("pull inicial 200 con server_timestamp", s == 200 and first.get("server_timestamp"), first)
    cursor = first["server_timestamp"]

    # Celular A creó un post OFFLINE hace 3 horas y recién ahora lo sube.
    time.sleep(1)
    late_id = str(uuid.uuid4())
    three_hours_ago = datetime.now(timezone.utc) - timedelta(hours=3)
    s, r = push(post_mutation(late_id, "Creado offline hace 3 horas", three_hours_ago))
    check("push del post tardío", s == 200 and r["processed_record_ids"] == [late_id], r)

    # Celular B vuelve a sincronizar con su cursor → DEBE recibirlo.
    s, second = call("GET", f"/api/v1/sync/pull?since={cursor}")
    ids = [p["id"] for p in second["delta"]["solidarity_posts"]] if s == 200 else []
    check("pull con since trae el post creado offline horas antes (bug corregido)",
          late_id in ids, second)
    late = next((p for p in second["delta"]["solidarity_posts"] if p["id"] == late_id), {})
    check("updated_at conserva la hora del celular (para LWW)",
          late.get("updated_at", "").startswith(iso(three_hours_ago)[:16]), late.get("updated_at"))
    check("server_updated_at lo pone el servidor (no el valor falsificado)",
          late.get("server_updated_at", "").startswith(datetime.now(timezone.utc).strftime("%Y-%m-%d")),
          late.get("server_updated_at"))

    # El cursor nuevo no vuelve a traer lo viejo (fuera del margen de seguridad).
    s, third = call("GET", f"/api/v1/sync/pull?since={iso(datetime.now(timezone.utc) + timedelta(minutes=1))}")
    check("pull con cursor futuro no trae nada", s == 200 and not any(third["delta"].values()), third)

    # Una edición posterior (LWW) también llega por server_updated_at.
    s, r = push(post_mutation(late_id, "Editado", datetime.now(timezone.utc)))
    s, fourth = call("GET", f"/api/v1/sync/pull?since={second['server_timestamp']}")
    edited = [p for p in fourth["delta"]["solidarity_posts"] if p["id"] == late_id]
    check("la edición llega en el siguiente pull", edited and edited[0]["title"] == "Editado", fourth)

    # ── 2. vulnerable_reports en el pull ──
    s, rep = call("POST", "/api/v1/emergency/sos", {
        "reporter_user_id": ME, "urgency_level": "CRITICA", "vulnerability_type": "ADULTO_MAYOR_SOLO",
        "description": "Adulto mayor solo", "lat": LAT, "lng": LNG})
    check("crear SOS por REST", s == 201, rep)
    s, pull_r = call("GET", f"/api/v1/sync/pull?since={fourth['server_timestamp']}")
    rep_ids = [x["id"] for x in pull_r["delta"].get("vulnerable_reports", [])] if s == 200 else []
    check("pull trae vulnerable_reports nuevos", rep.get("id") in rep_ids, pull_r)
    s, other = call("GET", "/api/v1/sync/pull", tenant=str(uuid.uuid4()))
    check("el token bloquea el pull de otro barrio", s == 403, other)
    s, att = call("PATCH", f"/api/v1/emergency/{rep.get('id')}/attend?helper_user_id={ME}")
    s, pull_a = call("GET", f"/api/v1/sync/pull?since={pull_r['server_timestamp']}")
    attended = [x for x in pull_a["delta"]["vulnerable_reports"] if x["id"] == rep.get("id")]
    check("atender el SOS (REST) llega en el pull por server_updated_at",
          attended and attended[0]["status"] == "VECINOS_EN_CAMINO", pull_a)

    # ── 3. Barrio y Modo Emergencia ──
    s, demo, = call("GET", "/api/v1/tenants/current")
    check("GET /tenants/current del barrio autenticado", s == 200 and demo["join_code"] == "BARRIO-01", demo)
    s, r = call("PATCH", "/api/v1/tenants/emergency-toggle", {}, tenant=DEMO)
    check("toggle sin cuerpo → 422", s == 422, r)
    s, r = call("GET", "/api/v1/tenants/current", tenant=None)
    check("tenants sin X-Tenant-ID → 400", s == 400, r)

    original = demo.get("is_emergency_active", False) if s == 200 else False
    try:
        s, on = call("PATCH", "/api/v1/tenants/emergency-toggle", {"is_emergency_active": True}, tenant=DEMO)
        check("activar emergencia del barrio demo", s == 200 and on["is_emergency_active"] is True, on)
        s, p = call("GET", "/api/v1/sync/pull?since=2999-01-01T00:00:00Z", tenant=DEMO)
        check("el pull siguiente trae tenant.is_emergency_active = true",
              s == 200 and p["tenant"]["is_emergency_active"] is True and p["tenant"]["registered"], p.get("tenant"))
        s, off = call("PATCH", "/api/v1/tenants/emergency-toggle", {"is_emergency_active": False}, tenant=DEMO)
        check("desactivar emergencia", s == 200 and off["is_emergency_active"] is False, off)
        s, p = call("GET", "/api/v1/sync/pull?since=2999-01-01T00:00:00Z", tenant=DEMO)
        check("el pull siguiente trae tenant.is_emergency_active = false",
              s == 200 and p["tenant"]["is_emergency_active"] is False, p.get("tenant"))
    finally:
        call("PATCH", "/api/v1/tenants/emergency-toggle", {"is_emergency_active": original}, tenant=DEMO)

    # ── Resumen ──
    print()
    for ok, name, detail in results:
        print(("OK   " if ok else "FAIL ") + name)
        if not ok:
            print("       ", detail)
    passed = sum(1 for ok, _, _ in results if ok)
    print(f"\n{passed}/{len(results)} pruebas OK  (barrio de prueba {T})")
    return 0 if passed == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
