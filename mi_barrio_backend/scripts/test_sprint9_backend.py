"""Pruebas del backend del Sprint 9 (Dev 1) contra el servidor levantado.

Uso (con uvicorn corriendo y la misma DATABASE_URL en el entorno o en .env):
    venv\\Scripts\\python.exe scripts\\test_sprint9_backend.py [http://localhost:8000]

Cubre:
- GET /api/v1/tenants/by-code/{code}: público, datos mínimos, 404 y 422.
  (El límite de 30 consultas por IP se prueba solo con MB_TEST_RATE_LIMIT=1, porque
  deja bloqueada la IP 5 minutos.)
- Migración B: redes y perfil de publicador suben por /sync/push (fila propia) con
  validaciones, y el vecino las recupera con GET /api/v1/users/me.
- /auth/register con código de barrio cubre el "quick-register" del plan.
Crea un barrio de prueba propio (nunca toca BARRIO-01).
"""
import os
import sys
import uuid
from datetime import datetime, timedelta, timezone

from _test_env import http, isolated_neighborhood, register

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

BASE = (sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8000").rstrip("/")
results: list[tuple[bool, str, str]] = []


def check(name, ok, detail=""):
    results.append((bool(ok), name, detail))
    print(f"{'OK  ' if ok else 'FALLA'} {name}" + (f"  -> {str(detail)[:250]}" if not ok else ""))


def now(delta_s=0):
    return (datetime.now(timezone.utc) + timedelta(seconds=delta_s)).isoformat().replace("+00:00", "Z")


def main() -> int:
    s, _ = http(BASE, "GET", "/health")
    if s != 200:
        print(f"Backend no disponible en {BASE}")
        return 2
    hood = isolated_neighborhood(BASE, "Pruebas Sprint 9")
    T, CODE = hood["tenant_id"], hood["join_code"]

    # ── Barrio por código (público) ──
    s, b = http(BASE, "GET", f"/api/v1/tenants/by-code/{CODE}")
    check("by-code sin sesión -> 200 con nombre y centro", s == 200 and b.get("name") == "Pruebas Sprint 9"
          and b.get("join_code") == CODE and "center_lat" in b, f"{s} {b}")
    check("by-code no revela id ni estado de emergencia",
          isinstance(b, dict) and "id" not in b and "is_emergency_active" not in b, b)
    s, b = http(BASE, "GET", f"/api/v1/tenants/by-code/{CODE.lower()}")
    check("by-code acepta minúsculas", s == 200 and b.get("join_code") == CODE, f"{s}")
    s, b = http(BASE, "GET", "/api/v1/tenants/by-code/NO-EXISTE-99")
    check("código inexistente -> 404", s == 404, f"{s} {b}")
    s, b = http(BASE, "GET", "/api/v1/tenants/by-code/%27OR1%3D1")
    check("código con caracteres raros -> 422", s == 422, f"{s}")

    # ── Registro con código (lo que el plan llamaba quick-register) ──
    vecino = register(BASE, CODE, "VECINO", "Rosa Quispe")
    otro = register(BASE, CODE, "VECINO", "Luis Paz")
    check("registro con código de barrio devuelve token", bool(vecino["token"]))

    def call(method, path, body=None, token=vecino["token"], tenant=T):
        return http(BASE, method, path, body, tenant=tenant, token=token)

    def push_profile(token, user_id, **fields):
        payload = {"id": user_id, "full_name": "Rosa Quispe", "phone": "987654321",
                   "home_lat": -5.1945, "home_lng": -80.6328, "tutorial_completed": True,
                   "is_deleted": False, "updated_at": now()}
        payload.update(fields)
        s, b = call("POST", "/api/v1/sync/push", {"client_sync_timestamp": now(), "mutations": [
            {"target_table": "users", "record_id": user_id, "operation": "UPSERT", "payload": payload}]},
            token=token)
        return s, (b.get("processed_record_ids", []) if isinstance(b, dict) else []), b

    # ── Perfil propio ──
    s, me = call("GET", "/api/v1/users/me")
    check("GET /users/me trae el perfil propio", s == 200 and me.get("id") == vecino["id"]
          and me.get("full_name") == "Rosa Quispe" and me.get("whatsapp") is None, f"{s} {me}")

    s, ok, b = push_profile(
        vecino["token"], vecino["id"], whatsapp="+51 987 654 321",
        facebook_url="https://facebook.com/rosa.quispe", instagram_url="https://instagram.com/rosa",
        publisher_type="EMPRENDEDOR", publisher_category="GASFITERIA", publisher_name="Gasfitería Rosa",
        photo_b64="/9j/" + "A" * 1000, role="ADMIN_BARRIO", email="hack@pruebas.test")
    check("sube redes y perfil de publicador por sync", ok == [vecino["id"]], b)
    s, me = call("GET", "/api/v1/users/me")
    check("GET /users/me devuelve las redes guardadas",
          s == 200 and me["whatsapp"] == "+51 987 654 321" and me["instagram_url"] == "https://instagram.com/rosa"
          and me["publisher_name"] == "Gasfitería Rosa" and me["photo_b64"].startswith("/9j/"), me)
    check("el sync no deja cambiar el rol ni el correo",
          me.get("role") == "VECINO" and me.get("email") == vecino["email"], me)

    invalid = {
        "WhatsApp con letras": {"whatsapp": "llámame"},
        "Facebook que no es enlace": {"facebook_url": "facebook.com/rosa"},
        "enlace javascript:": {"instagram_url": "javascript:alert(1)"},
        "tipo de publicador inválido": {"publisher_type": "MULTINACIONAL"},
        "nombre de negocio de 121 caracteres": {"publisher_name": "x" * 121},
        "foto de más de 110 KB": {"photo_b64": "A" * 110_001},
    }
    for name, fields in invalid.items():
        s, ok, b = push_profile(vecino["token"], vecino["id"], **fields)
        check(f"sync rechaza {name}", s == 200 and not ok, b)

    s, ok, b = push_profile(vecino["token"], vecino["id"], whatsapp=None, facebook_url=None)
    s2, me = call("GET", "/api/v1/users/me")
    check("se pueden borrar redes (null)", ok == [vecino["id"]] and me["whatsapp"] is None
          and me["facebook_url"] is None and me["instagram_url"] == "https://instagram.com/rosa", me)

    s, ok, b = push_profile(otro["token"], vecino["id"], full_name="Me adueño", whatsapp="+51 900 000 000")
    s2, me = call("GET", "/api/v1/users/me")
    check("nadie puede editar el perfil de otro vecino", not ok and me["full_name"] == "Rosa Quispe", f"{b} | {me}")

    s, b = call("GET", "/api/v1/users/me", token=None)
    check("GET /users/me sin token -> 401", s == 401, f"{s}")
    s, b = call("GET", "/api/v1/users/me", tenant=str(uuid.uuid4()))
    check("GET /users/me con otro barrio -> 403", s == 403, f"{s}")
    s, b = call("GET", "/api/v1/users/me", token=otro["token"])
    check("cada vecino solo ve su propio perfil", s == 200 and b["id"] == otro["id"] and b["whatsapp"] is None, b)

    # ── Límite de consultas por código (opcional) ──
    if os.getenv("MB_TEST_RATE_LIMIT") == "1":
        codes = [http(BASE, "GET", f"/api/v1/tenants/by-code/NO-{i:04d}")[0] for i in range(40)]
        check("by-code: tras 30 consultas por IP responde 429", 429 in codes, codes[-5:])
    else:
        print("OMITIDO: límite de 30 consultas por IP en by-code (define MB_TEST_RATE_LIMIT=1)")

    failed = [r for r in results if not r[0]]
    print(f"\n{len(results) - len(failed)}/{len(results)} pruebas OK")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
