"""Prueba de humo de TODOS los endpoints de la API contra el backend levantado.

Uso (con uvicorn corriendo y la misma DATABASE_URL en el entorno o en .env):
    venv\\Scripts\\python.exe scripts\\smoke_test_api.py [http://localhost:8000]

Crea un barrio de prueba propio (nunca toca el barrio demo BARRIO-01), con un
vecino, una comerciante y el administrador del barrio, todos con sesión real.
"""
import sys
import uuid
from datetime import datetime, timedelta, timezone

from _test_env import (
    http,
    isolated_neighborhood,
    register,
    remove_platform_admin,
    temporary_platform_admin,
)

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

BASE = (sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8000").rstrip("/")
LAT, LNG = -5.1945, -80.6328

results: list[tuple[bool, str, str]] = []


def check(name, ok, detail=""):
    results.append((bool(ok), name, detail))
    print(f"{'OK  ' if ok else 'FALLA'} {name}" + (f"  -> {str(detail)[:1000]}" if detail and not ok else ""))


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
    vecino2 = register(BASE, hood["join_code"], "VECINO", "Vecino smoke dos")
    comerciante = register(BASE, hood["join_code"], "COMERCIANTE", "Comerciante smoke")
    ajeno = register(BASE, other["join_code"], "VECINO", "Vecino de otro barrio")
    ME, PROVIDER = vecino["id"], comerciante["id"]

    def call(method, path, body=None, *, who=vecino, tenant=None, query=""):
        token = who["token"] if isinstance(who, dict) else who
        return http(BASE, method, path + query, body, tenant=tenant or TENANT, token=token)

    # ── Seguridad básica ──
    s, b = http(BASE, "GET", "/api/v1/services", tenant=TENANT)
    check("sin token -> 401", s == 401, f"{s} {b}")
    s, restored_user = call("GET", "/api/v1/auth/me")
    check("GET /auth/me restaura la sesión del usuario", s == 200 and restored_user.get("id") == ME,
          f"{s} {restored_user}")
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
    # Sin aprobación de la junta: el comerciante recién registrado publica al instante.
    check("comerciante nuevo queda activo al registrarse", comerciante["is_approved"] is True)
    s, svc = call("POST", "/api/v1/services", {
        "provider_user_id": PROVIDER, "category": "GASFITERIA",
        "title": "Gasfitero 24h", "description": "Prueba de humo",
        "is_available_in_emergency": True, "lat": LAT, "lng": LNG,
        "publisher_type": "EMPRENDEDOR", "publisher_name": "Gasfitería Smoke",
    }, who=comerciante)
    check("comerciante recién registrado publica su servicio",
          s == 201 and svc.get("publisher_type") == "EMPRENDEDOR", f"{s} {svc}")
    sync_service_id = str(uuid.uuid4())
    s, synced = call("POST", "/api/v1/sync/push", {"client_sync_timestamp": now(), "mutations": [{
        "target_table": "local_services", "record_id": sync_service_id, "operation": "UPSERT",
        "payload": {"id": sync_service_id, "provider_user_id": PROVIDER, "category": "CERRAJERIA",
                    "title": "Cerrajero sin esperar", "description": "", "lat": LAT, "lng": LNG,
                    "updated_at": now()}}]}, who=comerciante)
    check("...y también por sync (sin internet), sin esperar a la junta",
          s == 200 and synced["processed_record_ids"] == [sync_service_id], f"{s} {synced}")
    s, b = call("GET", "/api/v1/users/pending-merchants", who=hood["admin_token"])
    check("ya no existe la lista de comerciantes por aprobar", s in (404, 405, 422), f"{s}")
    sid = svc.get("id") if isinstance(svc, dict) else None

    s, my_services = call("GET", "/api/v1/services/mine", who=comerciante)
    check("comerciante lista sus servicios propios", s == 200 and any(x["id"] == sid for x in my_services), f"{s} {my_services}")

    s, b = call("GET", "/api/v1/services")
    check("GET /services", s == 200 and any(x["id"] == sid for x in b), f"{s} {str(b)[:200]}")
    s, b = call("GET", "/api/v1/services", query="?category=GASFITERIA&emergency_only=true")
    check("GET /services?category&emergency_only",
          s == 200 and all(x["category"] == "GASFITERIA" and x["is_available_in_emergency"] for x in b), f"{s}")
    s, b = call("GET", "/api/v1/services", who=ajeno, tenant=OTHER_TENANT)
    check("GET /services de otro barrio no ve el servicio", s == 200 and not any(x["id"] == sid for x in b))

    photo_b64 = "/9j/4AAQSkZJRgABAQAAAQABAAD/"
    s, b = call("POST", "/api/v1/services/endorse", {
        "service_id": sid, "endorser_user_id": ME, "rating": 4,
        "short_comment": "Bien", "photo_b64": photo_b64})
    check("POST /services/endorse (4 estrellas)", s == 200 and b["data"]["rating_avg"] == 4.0, f"{s} {b}")
    s, b = call("POST", "/api/v1/services/endorse", {
        "service_id": sid, "endorser_user_id": ME, "rating": 5,
        "short_comment": "Excelente", "photo_b64": photo_b64})
    check("endorse otra vez = upsert (200, count 1, avg 5)",
          s == 200 and b["data"]["endorsements_count"] == 1 and b["data"]["rating_avg"] == 5.0, f"{s} {b}")
    s, endorsements = call("GET", f"/api/v1/services/{sid}/endorsements")
    check("GET /services/{id}/endorsements no incluye fotos",
          s == 200 and len(endorsements) == 1 and endorsements[0]["rating"] == 5
          and endorsements[0]["short_comment"] == "Excelente"
          and "photo_b64" not in endorsements[0], f"{s} {endorsements}")
    endorsement_id = endorsements[0]["id"] if s == 200 and endorsements else str(uuid.uuid4())
    check("cada reseña dice quién la publicó",
          s == 200 and endorsements and endorsements[0].get("endorser_name") == "Vecina s.", f"{endorsements}")

    # ── Servicio completo: rubro nuevo, precio, fotos, edición ──
    full_id, foto = str(uuid.uuid4()), "/9j/4AAQSkZJRgABAQ"
    full = {"id": full_id, "provider_user_id": PROVIDER, "category": "ALBANILERIA",
            "title": "Albañilería y tarrajeo", "description": "Muros y pisos",
            "price_text": "S/ 80 el día", "photos": [foto, foto + "B"],
            "lat": LAT + 0.001, "lng": LNG, "updated_at": now()}
    s, b = call("POST", "/api/v1/sync/push", {"client_sync_timestamp": now(), "mutations": [
        {"target_table": "local_services", "record_id": full_id, "operation": "UPSERT", "payload": full}]},
        who=comerciante)
    check("servicio con rubro nuevo, precio y 2 fotos", s == 200 and b["processed_record_ids"] == [full_id], f"{s} {b}")
    s, b = call("GET", "/api/v1/sync/pull")
    row = next((x for x in b["delta"]["local_services"] if x["id"] == full_id), {}) if s == 200 else {}
    check("el pull trae precio y cuántas fotos (sin las fotos)",
          row.get("price_text") == "S/ 80 el día" and row.get("photo_count") == 2 and "photos" not in row, f"{row}")
    s, b = call("GET", f"/api/v1/services/{full_id}/photos")
    check("GET /services/{id}/photos", s == 200 and b.get("photos") == [foto, foto + "B"], f"{s}")
    edited = dict(full, title="Albañilería, tarrajeo y enchape", price_text="A tratar",
                  photos=[foto], updated_at=now(5))
    s, b = call("POST", "/api/v1/sync/push", {"client_sync_timestamp": now(), "mutations": [
        {"target_table": "local_services", "record_id": full_id, "operation": "UPSERT", "payload": edited}]},
        who=comerciante)
    s, b = call("GET", "/api/v1/services/mine", who=comerciante)
    row = next((x for x in b if x["id"] == full_id), {}) if s == 200 else {}
    check("el comerciante EDITA su servicio publicado",
          row.get("title") == "Albañilería, tarrajeo y enchape" and row.get("price_text") == "A tratar"
          and row.get("photo_count") == 1, f"{row}")
    s, b = call("POST", "/api/v1/sync/push", {"client_sync_timestamp": now(), "mutations": [
        {"target_table": "local_services", "record_id": full_id, "operation": "UPSERT",
         "payload": dict(edited, title="Hackeado", updated_at=now(9))}]})
    check("un vecino NO puede editar el servicio de otro", s == 200 and not b["processed_record_ids"], f"{b}")
    s, b = call("POST", "/api/v1/sync/push", {"client_sync_timestamp": now(), "mutations": [
        {"target_table": "local_services", "record_id": str(uuid.uuid4()), "operation": "UPSERT",
         "payload": dict(full, id=None, photos=[foto] * 5, updated_at=now())}]}, who=comerciante)
    check("más de 4 fotos se rechaza con motivo",
          s == 200 and b["rejected"] and "photos" in b["rejected"][0]["reason"], f"{b}")
    check("GET /services/{id}/endorsements marca has_photo (sin mandar la foto)",
          s == 200 and endorsements and endorsements[0].get("has_photo") is True, f"{endorsements}")
    s, photo = call("GET", f"/api/v1/endorsements/{endorsement_id}/photo")
    check("GET /endorsements/{id}/photo devuelve la foto separada",
          s == 200 and photo.get("photo_b64") == photo_b64, f"{s} {photo}")
    s, b = call("GET", f"/api/v1/endorsements/{uuid.uuid4()}/photo")
    check("GET foto de endorsement inexistente -> 404", s == 404, f"{s} {b}")
    s, b = call("GET", f"/api/v1/endorsements/{endorsement_id}/photo",
                who=ajeno, tenant=OTHER_TENANT)
    check("GET foto de otro barrio -> 404", s == 404, f"{s} {b}")
    s, b = call("POST", "/api/v1/services/endorse", {
        "service_id": sid, "endorser_user_id": vecino2["id"], "rating": 4}, who=vecino2)
    check("vecino puede dejar una calificación sin foto", s == 200, f"{s} {b}")
    s, endorsement_rows = call("GET", f"/api/v1/services/{sid}/endorsements")
    endorsement_for_reply = next(
        (row for row in endorsement_rows if row["endorser_user_id"] == vecino2["id"]),
        {},
    ) if s == 200 else {}
    recommendation_id = endorsement_for_reply.get("id")
    s, reply = call(
        "POST",
        f"/api/v1/services/{sid}/recommendations/{recommendation_id}/reply",
        {"reply": "Gracias por tu recomendación."},
        who=comerciante,
    )
    check("comerciante responde recomendación propia",
          s == 200 and reply.get("provider_reply") == "Gracias por tu recomendación."
          and reply.get("replied_at") is not None, f"{s} {reply}")
    s, b = call(
        "POST",
        f"/api/v1/services/{sid}/recommendations/{recommendation_id}/reply",
        {"reply": "Respuesta no autorizada"},
        who=vecino2,
    )
    check("vecino no puede responder reseñas -> 403", s == 403, f"{s} {b}")
    s, endorsements = call("GET", f"/api/v1/services/{sid}/endorsements")
    without_photo = next(
        (item for item in endorsements if item["endorser_user_id"] == vecino2["id"]),
        {},
    ) if s == 200 else {}
    s, b = call("GET", f"/api/v1/endorsements/{without_photo.get('id', uuid.uuid4())}/photo")
    check("GET foto de calificación sin foto -> 404", s == 404, f"{s} {b}")
    s, b = call("POST", "/api/v1/services/endorse", {"service_id": sid, "endorser_user_id": PROVIDER, "rating": 5}, who=comerciante)
    check("endorse el propio servicio -> 400", s == 400, f"{s} {b}")
    s, b = call("POST", "/api/v1/services/endorse", {"service_id": sid, "endorser_user_id": ME, "rating": 9})
    check("endorse rating 9 -> 422", s == 422, f"{s}")
    s, b = call("POST", "/api/v1/services/endorse", {"service_id": str(uuid.uuid4()), "endorser_user_id": ME, "rating": 3})
    check("endorse servicio inexistente -> 404", s == 404, f"{s} {b}")
    s, b = call("GET", "/api/v1/services")
    mine = next((x for x in b if x["id"] == sid), {}) if s == 200 else {}
    check("GET /services trae rating_avg", mine.get("rating_avg") == 4.5, f"{mine}")

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
    s, coordinate_post = call("POST", "/api/v1/solidarity", {
        "author_user_id": ME, "flow_type": "OFREZCO_AYUDA", "modality": "AYUDA_TEMPORAL",
        "title": "Favor para coordinar", "lat": LAT, "lng": LNG})
    coordinate_id = coordinate_post.get("id") if isinstance(coordinate_post, dict) else None
    s, b = call("PATCH", f"/api/v1/solidarity/{coordinate_id}/coordinate")
    check("autor no puede coordinar su propio favor -> 403", s == 403, f"{s} {b}")
    s, coordinated = call("PATCH", f"/api/v1/solidarity/{coordinate_id}/coordinate", who=comerciante)
    check("otro vecino coordina el favor cambiando solo status",
          s == 200 and coordinated.get("status") == "EN_COORDINACION"
          and all(coordinated.get(field) == coordinate_post.get(field) for field in (
              "author_user_id", "flow_type", "modality", "title", "description",
              "is_emergency_context", "lat", "lng", "is_deleted",
          )), f"{s} {coordinated}")
    s, b = call("PATCH", f"/api/v1/solidarity/{uuid.uuid4()}/coordinate")
    check("coordinar favor inexistente -> 404", s == 404, f"{s} {b}")
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
    s, b = call("PATCH", f"/api/v1/emergency/{rid}/attend")
    check("PATCH attend del propio SOS -> 403", s == 403, f"{s} {b}")
    # Quien pidió ayuda lo marca ATENDIDO (por sync); ya nadie puede "ir en camino".
    s, b = call("POST", "/api/v1/sync/push", {"client_sync_timestamp": now(), "mutations": [{
        "target_table": "vulnerable_reports", "record_id": rid, "operation": "UPSERT",
        "payload": {"id": rid, "reporter_user_id": ME, "status": "ATENDIDO", "updated_at": now(1)}}]})
    check("el autor marca su SOS como ATENDIDO (sync)", s == 200 and b["processed_record_ids"] == [rid], f"{s} {b}")
    s, b = call("PATCH", f"/api/v1/emergency/{rid}/attend", who=vecino2)
    check("PATCH attend de un SOS ATENDIDO -> 409", s == 409, f"{s} {b}")
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

    s, post_before_coordination = call("GET", f"/api/v1/solidarity/{post_id}")
    coordinate_payload = dict(post_before_coordination, status="EN_COORDINACION", updated_at=now())
    s, b = call("POST", "/api/v1/sync/push", {
        "client_sync_timestamp": now(),
        "mutations": [{
            "target_table": "solidarity_posts", "record_id": post_id,
            "operation": "UPSERT", "payload": coordinate_payload,
        }],
    }, who=comerciante)
    s2, coordinated_sync = call("GET", f"/api/v1/solidarity/{post_id}")
    check("sync permite coordinar favor ajeno sin modificar otros campos",
          s == 200 and b["processed_record_ids"] == [post_id]
          and coordinated_sync["status"] == "EN_COORDINACION"
          and all(coordinated_sync.get(field) == post_before_coordination.get(field) for field in (
              "author_user_id", "flow_type", "modality", "title", "description",
              "is_emergency_context", "lat", "lng", "is_deleted",
          )), f"{s} {b} {coordinated_sync}")

    tampered_coordination = dict(coordinate_payload, title="HACKEADO", updated_at=now(60))
    s, b = call("POST", "/api/v1/sync/push", {
        "client_sync_timestamp": now(),
        "mutations": [{
            "target_table": "solidarity_posts", "record_id": post_id,
            "operation": "UPSERT", "payload": tampered_coordination,
        }],
    }, who=comerciante)
    s2, p2 = call("GET", f"/api/v1/solidarity/{post_id}")
    check("sync rechaza editar otros campos al coordinar",
          s == 200 and not b["processed_record_ids"] and p2["title"] == "Sync v2", f"{s} {b} {p2}")

    s, b = call("POST", "/api/v1/sync/push", {
        "client_sync_timestamp": now(),
        "mutations": [{
            "target_table": "solidarity_posts", "record_id": post_id,
            "operation": "DELETE",
            "payload": dict(coordinate_payload, is_deleted=True, updated_at=now(60)),
        }],
    }, who=comerciante)
    s2, p2 = call("GET", f"/api/v1/solidarity/{post_id}")
    check("sync rechaza borrar un favor ajeno aunque esté coordinado",
          s == 200 and not b["processed_record_ids"] and s2 == 200 and not p2["is_deleted"],
          f"{s} {b} {s2} {p2}")

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

    # ── Detalle del favor: foto, comentarios, chat en tiempo real y reseñas ──
    fav_id = str(uuid.uuid4())
    photo = "/9j/4AAQSkZJRgABAQAAAQABAAD/"
    s, b = call("POST", "/api/v1/sync/push", {"client_sync_timestamp": now(), "mutations": [{
        "target_table": "solidarity_posts", "record_id": fav_id, "operation": "UPSERT", "payload": {
            "id": fav_id, "author_user_id": ME, "flow_type": "SOLICITO_AYUDA",
            "modality": "PRESTAMO_HERRAMIENTA", "title": "Necesito un taladro", "status": "DISPONIBLE",
            "is_emergency_context": False, "lat": LAT, "lng": LNG, "photo_b64": photo,
            "updated_at": now()}}]})
    check("favor con foto por sync", s == 200 and b["processed_record_ids"] == [fav_id], f"{s} {b}")
    s, b = call("GET", f"/api/v1/solidarity/{fav_id}/photo", who=vecino2)
    check("GET /solidarity/{id}/photo", s == 200 and b.get("photo_b64") == photo, f"{s}")
    s, b = call("GET", "/api/v1/sync/pull", who=vecino2)
    row = next((x for x in b["delta"]["solidarity_posts"] if x["id"] == fav_id), {}) if s == 200 else {}
    check("pull del favor: sin foto, con has_photo y nombre del autor",
          row.get("has_photo") is True and "photo_b64" not in row and row.get("author_name") == "Vecina s.",
          f"{row}")

    s, c = call("POST", f"/api/v1/solidarity/{fav_id}/comments", {"body": "Yo tengo uno"}, who=vecino2)
    check("POST comentario", s == 201 and c.get("author_name") == "Vecino s.", f"{s} {c}")
    s, b = call("GET", f"/api/v1/solidarity/{fav_id}/comments")
    check("GET comentarios", s == 200 and [x["body"] for x in b] == ["Yo tengo uno"], f"{s} {b}")
    s, b = call("DELETE", f"/api/v1/solidarity/{fav_id}/comments/{c.get('id')}")
    check("no puedes borrar el comentario de otro -> 403", s == 403, f"{s}")

    # Chat en tiempo real: la autora escucha por WebSocket y el vecino le escribe.
    from websockets.sync.client import connect as ws_connect
    import json as _json
    ws_url = BASE.replace("http", "ws", 1) + f"/api/v1/ws/chat?token={vecino['token']}&tenant={TENANT}"
    VEC2 = vecino2["id"]
    s, b = call("POST", f"/api/v1/chat/favor/{fav_id}/conversations/{VEC2}/messages", {"body": "Hola"})
    check("la autora no puede iniciar el chat -> 409", s == 409, f"{s} {b}")
    with ws_connect(ws_url, open_timeout=10) as ws:
        ws.send("ping")
        check("WebSocket conecta y responde pong", ws.recv(timeout=5) == "pong")
        s, m = call("POST", f"/api/v1/chat/favor/{fav_id}/conversations/{VEC2}/messages",
                    {"body": "Te lo presto hoy"}, who=vecino2)
        check("el vecino escribe por el favor", s == 201, f"{s} {m}")
        pushed = _json.loads(ws.recv(timeout=5))
        check("la autora lo recibe AL INSTANTE por WebSocket",
              pushed.get("type") == "chat_message" and pushed["message"]["body"] == "Te lo presto hoy", f"{pushed}")
    s, b = call("POST", f"/api/v1/chat/favor/{fav_id}/conversations/{VEC2}/messages", {"body": "¡Gracias!"})
    check("la autora responde", s == 201, f"{s} {b}")
    s, b = call("GET", f"/api/v1/chat/favor/{fav_id}/conversations")
    check("la autora ve la conversación", s == 200 and b and b[0]["message_count"] == 2, f"{s} {b}")
    s, b = call("GET", f"/api/v1/chat/favor/{fav_id}/conversations/{VEC2}/messages", who=comerciante)
    check("un tercero no lee el chat -> 403", s == 403, f"{s}")
    try:
        with ws_connect(BASE.replace("http", "ws", 1) + f"/api/v1/ws/chat?token=malo&tenant={TENANT}",
                        open_timeout=10) as ws:
            ws.recv(timeout=5)
        ws_rejected = False
    except Exception:
        ws_rejected = True
    check("WebSocket con token inválido se rechaza", ws_rejected)

    # Chat con el comerciante (por su servicio) + bandeja "Mis mensajes"
    s, m = call("POST", f"/api/v1/chat/service/{sid}/conversations/{ME}/messages",
                {"body": "¿Atiende el domingo?"})
    check("el vecino escribe al comerciante por su servicio", s == 201 and m.get("kind") == "service", f"{s} {m}")
    s, b = call("GET", f"/api/v1/chat/service/{sid}/conversations", who=comerciante)
    check("el comerciante ve la conversación con su nombre público",
          s == 200 and b and b[0]["other_name"] == "Vecina s." and b[0]["context_title"].startswith("Gasfitería Smoke"),
          f"{s} {b}")
    s, b = call("POST", f"/api/v1/chat/service/{sid}/conversations/{ME}/messages",
                {"body": "Sí, de 9 a 1"}, who=comerciante)
    check("el comerciante responde", s == 201, f"{s} {b}")
    s, b = call("GET", "/api/v1/chat/inbox")
    kinds = {x["kind"] for x in b} if s == 200 else set()
    check("Mis mensajes junta favores y servicios, el más reciente primero",
          s == 200 and kinds == {"favor", "service"} and b[0]["kind"] == "service"
          and b[0]["last_message"] == "Sí, de 9 a 1", f"{s} {b}")
    s, b = call("GET", f"/api/v1/chat/service/{sid}/conversations/{ME}/messages", who=vecino2)
    check("un tercero no lee el chat del servicio -> 403", s == 403, f"{s}")

    # Servicio retirado: el historial se sigue leyendo, pero no recibe mensajes nuevos.
    s, b = call("POST", f"/api/v1/chat/service/{full_id}/conversations/{ME}/messages", {"body": "¿Sigue?"})
    check("el vecino escribe por otro servicio", s == 201, f"{s} {b}")
    s, b = call("POST", "/api/v1/sync/push", {"client_sync_timestamp": now(), "mutations": [
        {"target_table": "local_services", "record_id": full_id, "operation": "UPSERT",
         "payload": dict(edited, is_deleted=True, updated_at=now(20))}]}, who=comerciante)
    check("el comerciante retira el servicio", s == 200 and b["processed_record_ids"] == [full_id], f"{s} {b}")
    s, b = call("GET", f"/api/v1/chat/service/{full_id}/conversations/{ME}/messages")
    check("el chat de un servicio retirado se sigue leyendo",
          s == 200 and [x["body"] for x in b] == ["¿Sigue?"], f"{s} {b}")
    s, b = call("POST", f"/api/v1/chat/service/{full_id}/conversations/{ME}/messages", {"body": "¿Hola?"})
    check("un servicio retirado ya no recibe mensajes -> 404", s == 404, f"{s} {b}")

    # Coordinar → completar → reseñas
    s, b = call("POST", f"/api/v1/solidarity/{fav_id}/reviews", {"rating": 5})
    check("reseña antes de completar -> 409", s == 409, f"{s}")
    s, b = call("PATCH", f"/api/v1/solidarity/{fav_id}/coordinate", who=vecino2)
    check("coordinar registra quién ayuda", s == 200 and b.get("coordinator_user_id") == VEC2, f"{s} {b}")
    s, b = call("POST", "/api/v1/sync/push", {"client_sync_timestamp": now(), "mutations": [{
        "target_table": "solidarity_posts", "record_id": fav_id, "operation": "UPSERT",
        "payload": {"id": fav_id, "author_user_id": ME, "status": "COMPLETADO", "updated_at": now(5)}}]})
    check("la autora marca COMPLETADO", s == 200 and b["processed_record_ids"] == [fav_id], f"{s} {b}")
    s, b = call("POST", f"/api/v1/solidarity/{fav_id}/reviews", {"rating": 5, "comment": "Muy amable"})
    check("la autora califica a quien ayudó",
          s == 201 and b.get("reviewed_user_id") == VEC2 and b.get("reviewed_name") == "Vecino s.", f"{s} {b}")
    s, b = call("POST", f"/api/v1/solidarity/{fav_id}/reviews", {"rating": 4})
    check("reseña duplicada -> 409", s == 409, f"{s}")
    s, b = call("POST", f"/api/v1/solidarity/{fav_id}/reviews", {"rating": 5}, who=vecino2)
    check("quien ayudó califica a la autora", s == 201 and b.get("reviewed_user_id") == ME, f"{s} {b}")
    s, b = call("POST", f"/api/v1/solidarity/{fav_id}/reviews", {"rating": 5}, who=comerciante)
    check("un tercero no deja reseña -> 403", s == 403, f"{s}")
    s, b = call("GET", f"/api/v1/solidarity/{fav_id}/reviews", who=comerciante)
    check("GET reseñas (públicas)", s == 200 and len(b) == 2, f"{s} {b}")

    # ── Superadministrador (plataforma) ──
    sa = temporary_platform_admin()
    try:
        s, b = http(BASE, "POST", "/api/v1/auth/login", {"email": sa["email"], "password": sa["password"]})
        user = b.get("user", {}) if isinstance(b, dict) else {}
        check("SUPER_ADMIN inicia sesión (sin barrio)",
              s == 200 and user.get("role") == "SUPER_ADMIN" and user.get("tenant") is None, f"{s} {b}")
        sa_token = b.get("access_token") if s == 200 else None
        s, b = http(BASE, "GET", "/api/v1/auth/me", token=sa_token)
        check("GET /auth/me del SUPER_ADMIN", s == 200 and b.get("role") == "SUPER_ADMIN", f"{s} {b}")
        admin_email = f"admin.{uuid.uuid4().hex[:8]}@pruebas.test"
        admin_password = uuid.uuid4().hex
        s, created = http(BASE, "POST", "/api/v1/platform/neighborhoods", {
            "neighborhood_name": "Smoke superadmin", "admin_full_name": "Junta smoke",
            "admin_email": admin_email, "admin_password": admin_password,
            "center_lat": LAT, "center_lng": LNG}, token=sa_token)
        new_code = created.get("neighborhood", {}).get("join_code") if isinstance(created, dict) else None
        check("SUPER_ADMIN crea un barrio de prueba con su administrador",
              s == 201 and bool(new_code) and created["administrator"]["role"] == "ADMIN_BARRIO", f"{s} {created}")
        s, b = http(BASE, "GET", "/api/v1/platform/neighborhoods", token=sa_token)
        row = next((x for x in b if x.get("invite_code") == new_code), {}) if s == 200 else {}
        check("GET /platform/neighborhoods lista el barrio con 1 administrador",
              row.get("admin_count") == 1, f"{s} {row}")
        s, b = http(BASE, "POST", "/api/v1/auth/login", {"email": admin_email, "password": admin_password})
        check("el administrador creado inicia sesión",
              s == 200 and b["user"]["role"] == "ADMIN_BARRIO", f"{s} {b}")
        s, b = http(BASE, "GET", "/api/v1/platform/neighborhoods", token=vecino["token"])
        check("un VECINO no gestiona barrios -> 403", s == 403, f"{s} {b}")
        s, b = http(BASE, "GET", "/api/v1/services", tenant=TENANT, token=sa_token)
        check("el SUPER_ADMIN no opera dentro de un barrio -> 403", s == 403, f"{s} {b}")
    finally:
        remove_platform_admin(sa["email"])

    failed = [r for r in results if not r[0]]
    print(f"\n{len(results) - len(failed)}/{len(results)} pruebas OK  (barrios de prueba {TENANT}, {OTHER_TENANT})")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
