"""Prueba de humo de TODOS los endpoints de la API contra el backend levantado.

Uso (con uvicorn corriendo y la misma DATABASE_URL en el entorno o en .env):
    venv\\Scripts\\python.exe scripts\\smoke_test_api.py [http://localhost:8000]

Crea un barrio de prueba propio (nunca toca el barrio demo BARRIO-01), con un
vecino, una comerciante y el administrador del barrio, todos con sesión real.
"""
import sys
import uuid
from datetime import datetime, timedelta, timezone

from _test_env import http, isolated_neighborhood, register

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

BASE = (sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8000").rstrip("/")
LAT, LNG = -5.1945, -80.6328

results: list[tuple[bool, str, str]] = []


def check(name, ok, detail=""):
    results.append((bool(ok), name, detail))
    print(f"{'OK  ' if ok else 'FALLA'} {name}" + (f"  -> {str(detail)[:250]}" if detail and not ok else ""))


def now(delta_s=0):
    return (datetime.now(timezone.utc) + timedelta(seconds=delta_s)).isoformat().replace("+00:00", "Z")


def main():
    s, b = http(BASE, "GET", "/health")
    check("GET /health", s == 200 and b["success"], f"{s} {b}")
    if s != 200:
        print(f"Backend no disponible en {BASE}. Levanta uvicorn primero.")
        sys.exit(2)

    # ── Barrios de prueba y cuentas reales ──
    hood = isolated_neighborhood(BASE, "Smoke test")
    other = isolated_neighborhood(BASE, "Smoke test (otro barrio)")
    TENANT, OTHER_TENANT = hood["tenant_id"], other["tenant_id"]
    vecino = register(BASE, hood["join_code"], "VECINO", "Vecina smoke")
    comerciante = register(BASE, hood["join_code"], "COMERCIANTE", "Comerciante smoke")
    ajeno = register(BASE, other["join_code"], "VECINO", "Vecino de otro barrio")
    ME, PROVIDER = vecino["id"], comerciante["id"]

    def call(method, path, body=None, *, who=vecino, tenant=None, query=""):
        token = who["token"] if isinstance(who, dict) else who
        return http(BASE, method, path + query, body, tenant=tenant or TENANT, token=token)

    # ── Seguridad básica ──
    s, b = http(BASE, "GET", "/api/v1/services", tenant=TENANT)
    check("sin token -> 401", s == 401, f"{s} {b}")
    s, b = http(BASE, "GET", "/api/v1/services", token=vecino["token"])
    check("sin X-Tenant-ID -> 400", s == 400, f"{s} {b}")
    s, b = http(BASE, "GET", "/api/v1/services", tenant="no-es-uuid", token=vecino["token"])
    check("X-Tenant-ID inválido -> 400", s == 400, f"{s} {b}")
    s, b = call("GET", "/api/v1/services", tenant=OTHER_TENANT)
    check("token de un barrio en otro barrio -> 403", s == 403, f"{s} {b}")
    s, b = http(BASE, "GET", "/openapi.json")
    check("Swagger muestra X-Tenant-ID en /services", s == 200 and "X-Tenant-ID" in str(b["paths"]["/api/v1/services"]))

    # ── Servicios (oficios) ──
    s, b = call("POST", "/api/v1/services", {
        "provider_user_id": ME, "category": "GASFITERIA", "title": "Vecina intenta ofrecer",
        "description": "x", "lat": LAT, "lng": LNG})
    check("un VECINO no puede publicar servicios -> 403", s == 403, f"{s} {b}")
    s, svc = call("POST", "/api/v1/services", {
        "provider_user_id": PROVIDER, "category": "GASFITERIA",
        "title": "Gasfitero 24h", "description": "Prueba de humo",
        "is_available_in_emergency": True, "lat": LAT, "lng": LNG,
        "publisher_type": "EMPRENDEDOR", "publisher_name": "Gasfitería Smoke",
    }, who=comerciante)
    check("POST /services (comerciante)", s == 201 and svc.get("publisher_type") == "EMPRENDEDOR", f"{s} {svc}")
    sid = svc.get("id") if isinstance(svc, dict) else None

    s, b = call("GET", "/api/v1/services")
    check("GET /services", s == 200 and any(x["id"] == sid for x in b), f"{s} {str(b)[:200]}")
    s, b = call("GET", "/api/v1/services", query="?category=GASFITERIA&emergency_only=true")
    check("GET /services?category&emergency_only",
          s == 200 and all(x["category"] == "GASFITERIA" and x["is_available_in_emergency"] for x in b), f"{s}")
    s, b = call("GET", "/api/v1/services", who=ajeno, tenant=OTHER_TENANT)
    check("GET /services de otro barrio no ve el servicio", s == 200 and not any(x["id"] == sid for x in b))

    s, b = call("POST", "/api/v1/services/endorse", {"service_id": sid, "endorser_user_id": ME, "rating": 4, "short_comment": "Bien"})
    check("POST /services/endorse (4 estrellas)", s == 200 and b["data"]["rating_avg"] == 4.0, f"{s} {b}")
    s, b = call("POST", "/api/v1/services/endorse", {"service_id": sid, "endorser_user_id": ME, "rating": 5})
    check("endorse otra vez = upsert (200, count 1, avg 5)",
          s == 200 and b["data"]["endorsements_count"] == 1 and b["data"]["rating_avg"] == 5.0, f"{s} {b}")
    s, b = call("POST", "/api/v1/services/endorse", {"service_id": sid, "endorser_user_id": PROVIDER, "rating": 5}, who=comerciante)
    check("endorse el propio servicio -> 400", s == 400, f"{s} {b}")
    s, b = call("POST", "/api/v1/services/endorse", {"service_id": sid, "endorser_user_id": ME, "rating": 9})
    check("endorse rating 9 -> 422", s == 422, f"{s}")
    s, b = call("POST", "/api/v1/services/endorse", {"service_id": str(uuid.uuid4()), "endorser_user_id": ME, "rating": 3})
    check("endorse servicio inexistente -> 404", s == 404, f"{s} {b}")
    s, b = call("GET", "/api/v1/services")
    mine = next((x for x in b if x["id"] == sid), {}) if s == 200 else {}
    check("GET /services trae rating_avg", mine.get("rating_avg") == 5.0, f"{mine}")

    # ── Red solidaria ──
    s, post = call("POST", "/api/v1/solidarity", {
        "author_user_id": ME, "flow_type": "SOLICITO_AYUDA", "modality": "PRESTAMO_HERRAMIENTA",
        "title": "Préstamo de escalera", "lat": LAT, "lng": LNG})
    check("POST /solidarity", s == 201 and post.get("status") == "DISPONIBLE", f"{s} {post}")
    pid = post.get("id") if isinstance(post, dict) else None
    s, b = call("POST", "/api/v1/solidarity", {
        "author_user_id": PROVIDER, "flow_type": "SOLICITO_AYUDA", "modality": "PRESTAMO_HERRAMIENTA",
        "title": "Suplantando", "lat": LAT, "lng": LNG})
    check("publicar a nombre de otro -> 403", s == 403, f"{s} {b}")
    s, b = call("GET", "/api/v1/solidarity", query="?flow_type=SOLICITO_AYUDA")
    check("GET /solidarity?flow_type", s == 200 and any(x["id"] == pid for x in b), f"{s}")
    s, b = call("GET", f"/api/v1/solidarity/{pid}")
    check("GET /solidarity/{id}", s == 200 and b["id"] == pid, f"{s} {b}")
    s, b = call("GET", f"/api/v1/solidarity/{pid}", who=ajeno, tenant=OTHER_TENANT)
    check("GET /solidarity/{id} de otro barrio -> 404", s == 404, f"{s}")
    s, b = call("DELETE", f"/api/v1/solidarity/{pid}", who=comerciante)
    check("borrar el post de otra persona -> 403", s == 403, f"{s} {b}")
    s, b = call("DELETE", f"/api/v1/solidarity/{pid}")
    check("DELETE /solidarity/{id} (borrado lógico)", s == 200, f"{s} {b}")
    s, b = call("GET", f"/api/v1/solidarity/{pid}")
    check("post eliminado ya no aparece -> 404", s == 404, f"{s}")

    # ── Emergencia ──
    s, rep = call("POST", "/api/v1/emergency/sos", {
        "reporter_user_id": ME, "urgency_level": "CRITICA", "vulnerability_type": "ADULTO_MAYOR_SOLO",
        "description": "Adulto mayor sin agua", "lat": LAT, "lng": LNG})
    check("POST /emergency/sos", s == 201 and rep.get("status") == "PENDIENTE_APOYO", f"{s} {rep}")
    rid = rep.get("id") if isinstance(rep, dict) else None
    s, b = call("GET", "/api/v1/emergency/board", query="?urgency_level=CRITICA")
    check("GET /emergency/board?urgency_level", s == 200 and any(x["id"] == rid for x in b), f"{s}")
    s, b = call("PATCH", f"/api/v1/emergency/{rid}/attend", who=comerciante)
    check("PATCH /emergency/{id}/attend (otra persona ayuda)",
          s == 200 and b.get("status") == "VECINOS_EN_CAMINO" and b.get("helper_user_id") == PROVIDER, f"{s} {b}")
    s, b = call("PATCH", f"/api/v1/emergency/{uuid.uuid4()}/attend")
    check("PATCH attend inexistente -> 404", s == 404, f"{s}")
    s, b = call("PATCH", "/api/v1/tenants/emergency-toggle", {"is_emergency_active": True})
    check("un VECINO no puede activar la emergencia del barrio -> 403", s == 403, f"{s} {b}")
    s, b = call("PATCH", "/api/v1/tenants/emergency-toggle", {"is_emergency_active": True}, who=hood["admin_token"])
    check("ADMIN_BARRIO activa la emergencia", s == 200 and b["is_emergency_active"] is True, f"{s} {b}")
    s, b = call("GET", "/api/v1/sync/pull", query="?since=2999-01-01T00:00:00Z")
    check("el vecino la recibe en el pull", s == 200 and b["tenant"]["is_emergency_active"] is True, f"{s}")
    call("PATCH", "/api/v1/tenants/emergency-toggle", {"is_emergency_active": False}, who=hood["admin_token"])

    # ── Sync: push ──
    s, pull0 = call("GET", "/api/v1/sync/pull")
    check("GET /sync/pull (snapshot)", s == 200 and "solidarity_posts" in pull0.get("delta", {}), f"{s}")
    since = pull0.get("server_timestamp") if isinstance(pull0, dict) else None

    post_id, svc2_id, rep2_id, endo_id = (str(uuid.uuid4()) for _ in range(4))
    t1 = now()
    s, b = call("POST", "/api/v1/sync/push", {"client_sync_timestamp": t1, "mutations": [
        {"target_table": "local_services", "record_id": svc2_id, "operation": "UPSERT", "payload": {
            "id": svc2_id, "provider_user_id": PROVIDER, "category": "CARPINTERIA",
            "title": "Carpintero sync", "description": "", "is_available_in_emergency": False,
            "lat": LAT, "lng": LNG, "updated_at": t1}}]}, who=comerciante)
    check("POST /sync/push servicio (comerciante)", s == 200 and b["processed_record_ids"] == [svc2_id], f"{s} {b}")
    batch = [
        {"target_table": "solidarity_posts", "record_id": post_id, "operation": "UPSERT", "payload": {
            "id": post_id, "author_user_id": ME, "flow_type": "OFREZCO_AYUDA", "modality": "AYUDA_TEMPORAL",
            "title": "Sync v1", "is_emergency_context": False, "status": "DISPONIBLE",
            "lat": LAT, "lng": LNG, "updated_at": t1}},
        {"target_table": "neighbor_endorsements", "record_id": endo_id, "operation": "UPSERT", "payload": {
            "id": endo_id, "service_id": svc2_id, "endorser_user_id": ME, "rating": 3,
            "short_comment": "sync", "updated_at": t1}},
        {"target_table": "vulnerable_reports", "record_id": rep2_id, "operation": "UPSERT", "payload": {
            "id": rep2_id, "reporter_user_id": ME, "urgency_level": "ALTA",
            "vulnerability_type": "FALTA_SUMINISTROS", "description": "sync SOS",
            "lat": LAT, "lng": LNG, "status": "PENDIENTE_APOYO", "updated_at": t1}},
        # Inválidas: se descartan solas, no tumban el lote.
        {"target_table": "neighbor_endorsements", "record_id": str(uuid.uuid4()), "operation": "UPSERT",
         "payload": {"service_id": str(uuid.uuid4()), "endorser_user_id": ME, "rating": 2, "updated_at": t1}},
        {"target_table": "solidarity_posts", "record_id": str(uuid.uuid4()), "operation": "UPSERT", "payload": {
            "author_user_id": ME, "flow_type": "HACK", "modality": "AYUDA_TEMPORAL", "title": "x",
            "status": "DISPONIBLE", "lat": 999, "lng": LNG, "updated_at": t1}},
    ]
    s, b = call("POST", "/api/v1/sync/push", {"client_sync_timestamp": t1, "mutations": batch})
    ok_ids = set(b.get("processed_record_ids", [])) if isinstance(b, dict) else set()
    check("POST /sync/push lote de 5 (3 válidos, 2 rechazados con motivo)",
          s == 200 and ok_ids == {post_id, endo_id, rep2_id} and len(b.get("rejected", [])) == 2, f"{s} {b}")

    s, b = call("POST", "/api/v1/sync/push", {"client_sync_timestamp": t1, "mutations": batch[:1]})
    check("push duplicado es idempotente", s == 200 and b["processed_record_ids"] == [post_id], f"{s} {b}")

    newer = dict(batch[0]["payload"], title="Sync v2", updated_at=now(5))
    call("POST", "/api/v1/sync/push", {"client_sync_timestamp": now(), "mutations": [dict(batch[0], payload=newer)]})
    older = dict(batch[0]["payload"], title="Sync VIEJO", updated_at=now(-3600))
    call("POST", "/api/v1/sync/push", {"client_sync_timestamp": now(), "mutations": [dict(batch[0], payload=older)]})
    s, b = call("GET", f"/api/v1/solidarity/{post_id}")
    check("LWW: gana el más nuevo, el viejo se ignora", s == 200 and b["title"] == "Sync v2", f"{s} {b}")

    hijack = dict(batch[0]["payload"], author_user_id=PROVIDER, title="HACKEADO", updated_at=now(60))
    s, b = call("POST", "/api/v1/sync/push", {"client_sync_timestamp": now(),
                "mutations": [dict(batch[0], payload=hijack)]}, who=comerciante)
    s2, p2 = call("GET", f"/api/v1/solidarity/{post_id}")
    check("por sync nadie edita el post de otra persona", s == 200 and not b["processed_record_ids"]
          and p2["title"] == "Sync v2" and p2["author_user_id"] == ME, f"{b} {p2}")

    s, b = call("POST", "/api/v1/sync/push", {"client_sync_timestamp": t1, "mutations": batch[:1]},
                who=ajeno, tenant=OTHER_TENANT)
    s2, b2 = call("GET", f"/api/v1/solidarity/{post_id}", who=ajeno, tenant=OTHER_TENANT)
    check("push con otro barrio no toca la fila original", s2 == 404 and not b["processed_record_ids"], f"{s2} {b}")

    big = {"client_sync_timestamp": now(), "mutations": [batch[0]] * 201}
    s, b = call("POST", "/api/v1/sync/push", big)
    check("lote de más de 200 cambios -> 413", s == 413, f"{s}")

    # ── Sync: pull ──
    s, b = call("GET", "/api/v1/sync/pull", query=f"?since={since}")
    delta = b.get("delta", {}) if isinstance(b, dict) else {}
    svc_row = next((x for x in delta.get("local_services", []) if x["id"] == svc2_id), {})
    check("GET /sync/pull?since trae el post nuevo",
          any(x["id"] == post_id for x in delta.get("solidarity_posts", [])), f"{s}")
    check("GET /sync/pull?since trae servicio con rating_avg y contador",
          svc_row.get("rating_avg") == 3.0 and svc_row.get("endorsements_count") == 1, f"{svc_row}")
    check("pull trae los SOS", any(x["id"] == rep2_id for x in delta.get("vulnerable_reports", [])))
    check("pull no manda fotos", all("photo_b64" not in x for x in delta.get("local_services", [])))
    s, b = call("GET", "/api/v1/sync/pull", query="?since=no-es-fecha")
    check("pull con since inválido -> 400", s == 400, f"{s}")
    s, b = call("GET", "/api/v1/sync/pull", who=ajeno, tenant=OTHER_TENANT)
    leaked = [x for v in b.get("delta", {}).values() for x in v if x.get("tenant_id") == TENANT] if s == 200 else []
    check("pull de otro barrio no filtra datos", s == 200 and not leaked, f"{s} {len(leaked)}")

    failed = [r for r in results if not r[0]]
    print(f"\n{len(results) - len(failed)}/{len(results)} pruebas OK  (barrios de prueba {TENANT}, {OTHER_TENANT})")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
