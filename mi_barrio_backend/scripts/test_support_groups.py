"""Pruebas de los grupos de apoyo (Sprint 8, Dev 1) contra el backend levantado.

Uso (con uvicorn corriendo y la misma DATABASE_URL en el entorno o en .env):
    venv\\Scripts\\python.exe scripts\\test_support_groups.py [http://localhost:8000]

Cubre GET/POST /api/v1/emergency/support-groups (permisos, orden por cercanía,
filtro, validaciones) y que los grupos bajen en el pull para usarlos sin internet.
Crea un barrio de prueba propio (nunca toca BARRIO-01).
"""
import sys
import uuid

from _test_env import http, isolated_neighborhood, register

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

BASE = (sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8000").rstrip("/")
LAT, LNG = -5.1945, -80.6328
results: list[tuple[bool, str, str]] = []


def check(name, ok, detail=""):
    results.append((bool(ok), name, detail))
    print(f"{'OK  ' if ok else 'FALLA'} {name}" + (f"  -> {str(detail)[:250]}" if not ok else ""))


def main() -> int:
    s, _ = http(BASE, "GET", "/health")
    if s != 200:
        print(f"Backend no disponible en {BASE}")
        return 2
    hood = isolated_neighborhood(BASE, "Pruebas grupos de apoyo")
    T, ADMIN = hood["tenant_id"], hood["admin_token"]
    vecino = register(BASE, hood["join_code"], "VECINO")

    def call(method, path, body=None, token=ADMIN, tenant=T):
        return http(BASE, method, path, body, tenant=tenant, token=token)

    # ── Registrar (solo ADMIN_BARRIO) ──
    groups = [
        {"name": "Olla común", "group_type": "ALIMENTOS", "lat": LAT + 0.02, "lng": LNG,
         "meeting_point": "Comedor popular", "contact_phone": "+51 987 654 321"},
        {"name": "Brigada de primeros auxilios", "group_type": "PRIMEROS_AUXILIOS", "lat": LAT + 0.001, "lng": LNG},
        {"name": "Albergue parroquial", "group_type": "ALBERGUE", "lat": LAT + 0.01, "lng": LNG},
        {"name": "Apoyo emocional", "group_type": "SALUD_MENTAL"},  # sin ubicación
    ]
    ids = []
    for g in groups:
        s, b = call("POST", "/api/v1/emergency/support-groups", g)
        check(f"ADMIN_BARRIO registra '{g['name']}'", s == 201 and b.get("tenant_id") == T, f"{s} {b}")
        ids.append(b.get("id") if isinstance(b, dict) else None)
    s, b = call("POST", "/api/v1/emergency/support-groups", {"name": "Pirata", "group_type": "RESCATE"},
                token=vecino["token"])
    check("VECINO no puede registrar grupos -> 403", s == 403, f"{s} {b}")
    s, b = call("POST", "/api/v1/emergency/support-groups", {"name": "X", "group_type": "PIRATAS"})
    check("group_type inválido al registrar -> 422", s == 422, f"{s}")
    s, b = call("POST", "/api/v1/emergency/support-groups", {"name": "Sin lng", "group_type": "RESCATE", "lat": LAT})
    check("lat sin lng al registrar -> 422", s == 422, f"{s} {b}")
    s, b = call("POST", "/api/v1/emergency/support-groups",
                {"name": "Tel malo", "group_type": "RESCATE", "contact_phone": "llámame"})
    check("teléfono inválido -> 422", s == 422, f"{s}")

    # ── Listar ──
    s, listed = call("GET", "/api/v1/emergency/support-groups", token=vecino["token"])
    names = [g["name"] for g in listed] if s == 200 else []
    check("VECINO lista los 4 grupos (sin lat/lng, por nombre)", names == sorted(names) and len(names) == 4,
          f"{s} {names}")
    s, near = call("GET", f"/api/v1/emergency/support-groups?lat={LAT}&lng={LNG}", token=vecino["token"])
    order = [g["name"] for g in near] if s == 200 else []
    check("con lat/lng: del más cercano al más lejano, sin ubicación al final",
          order == ["Brigada de primeros auxilios", "Albergue parroquial", "Olla común", "Apoyo emocional"], order)
    check("distance_km viene calculada", s == 200 and near[0]["distance_km"] is not None
          and near[0]["distance_km"] < 0.2 and near[-1]["distance_km"] is None, near[:1])
    s, only = call("GET", "/api/v1/emergency/support-groups?group_type=ALBERGUE", token=vecino["token"])
    check("filtro group_type=ALBERGUE", s == 200 and [g["name"] for g in only] == ["Albergue parroquial"], only)
    s, b = call("GET", f"/api/v1/emergency/support-groups?lat={LAT}", token=vecino["token"])
    check("lat sin lng -> 422", s == 422, f"{s}")
    s, b = call("GET", "/api/v1/emergency/support-groups", token=None)
    check("sin token -> 401", s == 401, f"{s}")
    s, b = call("GET", "/api/v1/emergency/support-groups", token=vecino["token"], tenant=str(uuid.uuid4()))
    check("token en otro barrio -> 403", s == 403, f"{s}")

    # ── Offline: bajan en el pull ──
    s, pull = call("GET", "/api/v1/sync/pull", token=vecino["token"])
    pulled = {g["id"] for g in pull.get("delta", {}).get("support_groups", [])} if s == 200 else set()
    check("el pull trae support_groups del barrio", set(ids) <= pulled, f"{s} {len(pulled)}")
    since = pull.get("server_timestamp") if s == 200 else None
    s, pull2 = call("GET", f"/api/v1/sync/pull?since={since}", token=vecino["token"])
    check("el pull incremental no los repite si no cambiaron",
          s == 200 and not [g for g in pull2["delta"].get("support_groups", []) if g["id"] in ids][4:], f"{s}")

    # ── El barrio demo trae sus 3 grupos de la migración ──
    demo = register(BASE, "BARRIO-01", "VECINO")
    s, demo_groups = http(BASE, "GET", "/api/v1/emergency/support-groups",
                          tenant="a1b2c3d4-e5f6-4a8b-9c0d-1e2f3a4b5c6d", token=demo["token"])
    check("BARRIO-01 tiene sus 3 grupos demo", s == 200 and len(demo_groups) >= 3, f"{s} {demo_groups}")

    failed = [r for r in results if not r[0]]
    print(f"\n{len(results) - len(failed)}/{len(results)} pruebas OK")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
