"""Prueba de humo de TODOS los endpoints de la API contra el backend levantado.

Uso (con uvicorn corriendo):
    venv\\Scripts\\python.exe scripts\\smoke_test_api.py [http://localhost:8000]

Crea datos de prueba en el barrio demo (títulos con prefijo "[SMOKE]") y
deja los posts marcados como eliminados. No necesita la contraseña de la BD.
"""
import json
import sys
import urllib.error
import urllib.request
import uuid
from datetime import datetime, timedelta, timezone

BASE = (sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8000").rstrip("/")
TENANT = "a1b2c3d4-e5f6-4a8b-9c0d-1e2f3a4b5c6d"
OTHER_TENANT = str(uuid.uuid4())
ME = "5f3a2c1b-1234-4abc-9def-0123456789ab"
PROVIDER = str(uuid.uuid4())
LAT, LNG = -5.1945, -80.6328

results: list[tuple[bool, str, str]] = []


def call(method, path, body=None, tenant=TENANT, query=""):
    headers = {"Content-Type": "application/json"}
    if tenant is not None:
        headers["X-Tenant-ID"] = tenant
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(f"{BASE}{path}{query}", data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            raw = r.read().decode()
            return r.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw)
        except ValueError:
            return e.code, raw


def check(name, ok, detail=""):
    results.append((bool(ok), name, detail))
    print(f"{'OK  ' if ok else 'FALLA'} {name}" + (f"  -> {detail}" if detail and not ok else ""))


def now(delta_s=0):
    return (datetime.now(timezone.utc) + timedelta(seconds=delta_s)).isoformat().replace("+00:00", "Z")


def main():
    # ── Sistema y multi-tenant ──
    s, b = call("GET", "/health", tenant=None)
    check("GET /health", s == 200 and b["success"], f"{s} {b}")
    s, b = call("GET", "/api/v1/services", tenant=None)
    check("sin X-Tenant-ID -> 400", s == 400, f"{s} {b}")
    s, b = call("GET", "/api/v1/services", tenant="no-es-uuid")
    check("X-Tenant-ID inválido -> 400", s == 400, f"{s} {b}")
    s, b = call("GET", "/openapi.json", tenant=None)
    params = json.dumps(b.get("paths", {}).get("/api/v1/services", {})) if s == 200 else ""
    check("Swagger muestra X-Tenant-ID en /services", "X-Tenant-ID" in params)

    # ── Servicios (oficios) ──
    s, svc = call("POST", "/api/v1/services", {
        "provider_user_id": PROVIDER, "category": "GASFITERIA",
        "title": "[SMOKE] Gasfitero 24h", "description": "Prueba de humo",
        "is_available_in_emergency": True, "lat": LAT, "lng": LNG,
        "publisher_type": "EMPRENDEDOR", "publisher_name": "Gasfitería Smoke",
    })
    check("POST /services", s == 201 and svc.get("publisher_type") == "EMPRENDEDOR", f"{s} {svc}")
    sid = svc.get("id") if isinstance(svc, dict) else None

    s, b = call("GET", "/api/v1/services")
    check("GET /services", s == 200 and any(x["id"] == sid for x in b), f"{s} {str(b)[:200]}")
    s, b = call("GET", "/api/v1/services", query="?category=GASFITERIA&emergency_only=true")
    check("GET /services?category&emergency_only",
          s == 200 and all(x["category"] == "GASFITERIA" and x["is_available_in_emergency"] for x in b), f"{s}")
    s, b = call("GET", "/api/v1/services", tenant=OTHER_TENANT)
    check("GET /services de otro barrio no ve el servicio", s == 200 and not any(x["id"] == sid for x in b))

    s, b = call("POST", "/api/v1/services/endorse",
                {"service_id": sid, "endorser_user_id": ME, "rating": 4, "short_comment": "Bien"})
    check("POST /services/endorse (4 estrellas)", s == 200 and b["data"]["rating_avg"] == 4.0, f"{s} {b}")
    s, b = call("POST", "/api/v1/services/endorse",
                {"service_id": sid, "endorser_user_id": ME, "rating": 5})
    check("endorse otra vez = upsert (200, count 1, avg 5)",
          s == 200 and b["data"]["endorsements_count"] == 1 and b["data"]["rating_avg"] == 5.0, f"{s} {b}")
    s, b = call("POST", "/api/v1/services/endorse",
                {"service_id": sid, "endorser_user_id": PROVIDER, "rating": 5})
    check("endorse el propio servicio -> 400", s == 400, f"{s} {b}")
    s, b = call("POST", "/api/v1/services/endorse",
                {"service_id": sid, "endorser_user_id": ME, "rating": 9})
    check("endorse rating 9 -> 422", s == 422, f"{s}")
    s, b = call("POST", "/api/v1/services/endorse",
                {"service_id": str(uuid.uuid4()), "endorser_user_id": ME, "rating": 3})
    check("endorse servicio inexistente -> 404", s == 404, f"{s} {b}")
    s, b = call("GET", "/api/v1/services")
    mine = next((x for x in b if x["id"] == sid), {}) if s == 200 else {}
    check("GET /services trae rating_avg", mine.get("rating_avg") == 5.0, f"{mine}")

    # ── Red solidaria ──
    s, post = call("POST", "/api/v1/solidarity", {
        "author_user_id": ME, "flow_type": "SOLICITO_AYUDA", "modality": "PRESTAMO_HERRAMIENTA",
        "title": "[SMOKE] Préstamo de escalera", "lat": LAT, "lng": LNG,
    })
    check("POST /solidarity", s == 201 and post.get("status") == "DISPONIBLE", f"{s} {post}")
    pid = post.get("id") if isinstance(post, dict) else None
    s, b = call("GET", "/api/v1/solidarity", query="?flow_type=SOLICITO_AYUDA")
    check("GET /solidarity?flow_type", s == 200 and any(x["id"] == pid for x in b), f"{s}")
    s, b = call("GET", f"/api/v1/solidarity/{pid}")
    check("GET /solidarity/{id}", s == 200 and b["id"] == pid, f"{s} {b}")
    s, b = call("GET", f"/api/v1/solidarity/{pid}", tenant=OTHER_TENANT)
    check("GET /solidarity/{id} de otro barrio -> 404", s == 404, f"{s}")
    s, b = call("DELETE", f"/api/v1/solidarity/{pid}")
    check("DELETE /solidarity/{id} (borrado lógico)", s == 200, f"{s} {b}")
    s, b = call("GET", f"/api/v1/solidarity/{pid}")
    check("post eliminado ya no aparece -> 404", s == 404, f"{s}")

    # ── Emergencia ──
    s, rep = call("POST", "/api/v1/emergency/sos", {
        "reporter_user_id": ME, "urgency_level": "CRITICA", "vulnerability_type": "ADULTO_MAYOR_SOLO",
        "description": "[SMOKE] Adulto mayor sin agua", "lat": LAT, "lng": LNG,
    })
    check("POST /emergency/sos", s == 201 and rep.get("status") == "PENDIENTE_APOYO", f"{s} {rep}")
    rid = rep.get("id") if isinstance(rep, dict) else None
    s, b = call("GET", "/api/v1/emergency/board", query="?urgency_level=CRITICA")
    check("GET /emergency/board?urgency_level", s == 200 and any(x["id"] == rid for x in b), f"{s}")
    s, b = call("PATCH", f"/api/v1/emergency/{rid}/attend", query=f"?helper_user_id={ME}")
    check("PATCH /emergency/{id}/attend", s == 200 and b.get("status") == "VECINOS_EN_CAMINO"
          and b.get("helper_user_id") == ME, f"{s} {b}")
    s, b = call("PATCH", f"/api/v1/emergency/{uuid.uuid4()}/attend", query=f"?helper_user_id={ME}")
    check("PATCH attend inexistente -> 404", s == 404, f"{s}")

    # ── Sync: push ──
    s, pull0 = call("GET", "/api/v1/sync/pull")
    check("GET /sync/pull (snapshot)", s == 200 and "solidarity_posts" in pull0.get("delta", {}), f"{s}")
    since = pull0.get("server_timestamp") if isinstance(pull0, dict) else None

    post_id, svc2_id, rep2_id = str(uuid.uuid4()), str(uuid.uuid4()), str(uuid.uuid4())
    endo_id = str(uuid.uuid4())
    t1 = now()
    batch = [
        {"target_table": "solidarity_posts", "record_id": post_id, "operation": "UPSERT", "payload": {
            "id": post_id, "author_user_id": ME, "flow_type": "OFREZCO_AYUDA", "modality": "AYUDA_TEMPORAL",
            "title": "[SMOKE] Sync v1", "is_emergency_context": False, "status": "DISPONIBLE",
            "lat": LAT, "lng": LNG, "updated_at": t1}},
        {"target_table": "local_services", "record_id": svc2_id, "operation": "UPSERT", "payload": {
            "id": svc2_id, "provider_user_id": PROVIDER, "category": "CARPINTERIA",
            "title": "[SMOKE] Carpintero sync", "description": "", "is_available_in_emergency": False,
            "lat": LAT, "lng": LNG, "updated_at": t1}},
        {"target_table": "neighbor_endorsements", "record_id": endo_id, "operation": "UPSERT", "payload": {
            "id": endo_id, "service_id": svc2_id, "endorser_user_id": ME, "rating": 3,
            "short_comment": "sync", "updated_at": t1}},
        {"target_table": "vulnerable_reports", "record_id": rep2_id, "operation": "UPSERT", "payload": {
            "id": rep2_id, "reporter_user_id": ME, "urgency_level": "ALTA",
            "vulnerability_type": "FALTA_SUMINISTROS", "description": "[SMOKE] sync SOS",
            "lat": LAT, "lng": LNG, "status": "PENDIENTE_APOYO", "updated_at": t1}},
        # Inválida: califica un servicio que no existe -> se descarta sola, no tumba el lote.
        {"target_table": "neighbor_endorsements", "record_id": str(uuid.uuid4()), "operation": "UPSERT",
         "payload": {"service_id": str(uuid.uuid4()), "endorser_user_id": ME, "rating": 2, "updated_at": t1}},
    ]
    s, b = call("POST", "/api/v1/sync/push", {"client_sync_timestamp": t1, "mutations": batch})
    ok_ids = set(b.get("processed_record_ids", [])) if isinstance(b, dict) else set()
    check("POST /sync/push lote de 5 (4 válidos)", s == 200 and ok_ids == {post_id, svc2_id, endo_id, rep2_id},
          f"{s} {b}")

    s, b = call("POST", "/api/v1/sync/push", {"client_sync_timestamp": t1, "mutations": batch[:1]})
    check("push duplicado es idempotente", s == 200 and b["processed_record_ids"] == [post_id], f"{s} {b}")

    newer = dict(batch[0]["payload"], title="[SMOKE] Sync v2", updated_at=now(5))
    call("POST", "/api/v1/sync/push", {"client_sync_timestamp": now(),
         "mutations": [dict(batch[0], payload=newer)]})
    older = dict(batch[0]["payload"], title="[SMOKE] Sync VIEJO", updated_at=now(-3600))
    call("POST", "/api/v1/sync/push", {"client_sync_timestamp": now(),
         "mutations": [dict(batch[0], payload=older)]})
    s, b = call("GET", f"/api/v1/solidarity/{post_id}")
    check("LWW: gana el más nuevo, el viejo se ignora", s == 200 and b["title"] == "[SMOKE] Sync v2", f"{s} {b}")

    s, b = call("POST", "/api/v1/sync/push", {"client_sync_timestamp": t1, "mutations": batch[:1]},
                tenant=OTHER_TENANT)
    s2, b2 = call("GET", f"/api/v1/solidarity/{post_id}", tenant=OTHER_TENANT)
    check("push con otro barrio no toca la fila original", s2 == 404, f"{s2}")

    # ── Sync: pull ──
    s, b = call("GET", "/api/v1/sync/pull", query=f"?since={since}")
    delta = b.get("delta", {}) if isinstance(b, dict) else {}
    svc_row = next((x for x in delta.get("local_services", []) if x["id"] == svc2_id), {})
    check("GET /sync/pull?since trae el post nuevo",
          any(x["id"] == post_id for x in delta.get("solidarity_posts", [])), f"{s}")
    check("GET /sync/pull?since trae servicio con rating_avg y contador",
          svc_row.get("rating_avg") == 3.0 and svc_row.get("endorsements_count") == 1, f"{svc_row}")
    check("pull no manda fotos", all("photo_b64" not in x for x in delta.get("local_services", [])))
    s, b = call("GET", "/api/v1/sync/pull", query="?since=no-es-fecha")
    check("pull con since inválido -> 400", s == 400, f"{s}")
    s, b = call("GET", "/api/v1/sync/pull", tenant=OTHER_TENANT)
    leaked = [x for v in b.get("delta", {}).values() for x in v if x.get("tenant_id") == TENANT] if s == 200 else []
    check("pull de otro barrio no filtra datos", s == 200 and not leaked, f"{s} {len(leaked)}")

    # Limpieza: el post sincronizado queda eliminado.
    call("DELETE", f"/api/v1/solidarity/{post_id}")

    failed = [r for r in results if not r[0]]
    print(f"\n{len(results) - len(failed)}/{len(results)} pruebas OK")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
