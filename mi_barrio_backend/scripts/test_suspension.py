"""Suspensión de cuentas: 3 vecinos reportan → cuenta suspendida → el jefe
del barrio la reactiva.

Uso (backend local con AUTH_DEBUG_CODES=1):
    .venv/bin/python scripts/test_suspension.py http://127.0.0.1:8000

Crea su propio barrio de prueba (no toca ningún barrio real).
"""
import sys
import uuid
from datetime import datetime, timezone

from _test_env import http, isolated_neighborhood, register

BASE = (sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:8000").rstrip("/")
results: list[bool] = []


def check(name: str, ok: bool, detail="") -> None:
    results.append(ok)
    print(("OK   " if ok else "FAIL ") + name + ("" if ok else f"  -> {detail}"))


def now() -> str:
    return datetime.now(timezone.utc).isoformat()


def push(who: dict, table: str, payload: dict, tenant: str):
    rid = payload["id"]
    return http(BASE, "POST", "/api/v1/sync/push", {"client_sync_timestamp": now(), "mutations": [{
        "target_table": table, "record_id": rid, "operation": "UPSERT",
        "payload": {**payload, "updated_at": now()}}]}, tenant=tenant, token=who["token"])


def new_post(who: dict, tenant: str, title: str) -> str:
    pid = str(uuid.uuid4())
    s, r = push(who, "solidarity_posts", {
        "id": pid, "author_user_id": who["id"], "flow_type": "OFREZCO_AYUDA",
        "modality": "DONACION_MATERIAL", "title": title, "status": "DISPONIBLE",
        "is_emergency_context": False, "lat": -5.19, "lng": -80.63, "is_deleted": False}, tenant)
    assert s == 200 and r["processed_record_ids"] == [pid], (s, r)
    return pid


def report(who: dict, tenant: str, post_id: str) -> None:
    rid = str(uuid.uuid4())
    s, r = push(who, "content_reports", {
        "id": rid, "reporter_user_id": who["id"], "target_type": "SOLIDARITY_POST",
        "target_id": post_id, "reason": "OFENSIVO"}, tenant)
    assert s == 200 and r["processed_record_ids"] == [rid], (s, r)


def main() -> int:
    hood = isolated_neighborhood(BASE, "Suspensiones")
    tenant, admin = hood["tenant_id"], hood["admin_token"]
    author = register(BASE, hood["join_code"], "VECINO", "Autor reportado")
    vecinos = [register(BASE, hood["join_code"], "VECINO", f"Vecino {i}") for i in range(4)]

    p1 = new_post(author, tenant, "Primera publicación")
    p2 = new_post(author, tenant, "Segunda publicación")
    # 2 vecinos reportan una y 1 vecino otra: 3 vecinos distintos en total.
    report(vecinos[0], tenant, p1)
    report(vecinos[1], tenant, p1)
    s, r = http(BASE, "GET", "/api/v1/auth/me", token=author["token"])
    check("con 2 reportes la cuenta sigue activa", s == 200, f"{s} {r}")
    report(vecinos[1], tenant, p2)  # mismo vecino otra vez: no suma
    s, r = http(BASE, "GET", "/api/v1/auth/me", token=author["token"])
    check("el mismo vecino reportando 2 veces cuenta 1", s == 200, f"{s} {r}")
    report(vecinos[2], tenant, p2)

    s, r = http(BASE, "GET", "/api/v1/auth/me", token=author["token"])
    check("con 3 vecinos distintos la cuenta queda suspendida (401)",
          s == 401 and "suspendida" in str(r).lower(), f"{s} {r}")
    s, r = http(BASE, "POST", "/api/v1/auth/login",
                {"email": author["email"], "password": author["password"]})
    check("al ingresar le dice que hable con el jefe del barrio (y su nombre)",
          s == 403 and "jefe de tu barrio" in str(r) and "Admin de pruebas" in str(r), f"{s} {r}")

    s, r = http(BASE, "GET", "/api/v1/moderation/suspended", tenant=tenant, token=vecinos[3]["token"])
    check("un vecino no ve la lista de suspendidos (403)", s == 403, f"{s} {r}")
    s, r = http(BASE, "GET", "/api/v1/moderation/suspended", tenant=tenant, token=admin)
    item = next((x for x in (r or []) if x["user_id"] == author["id"]), None) if s == 200 else None
    check("el jefe del barrio ve la cuenta suspendida con 3 reportes",
          item is not None and item["report_count"] == 3, f"{s} {r}")

    s, r = http(BASE, "POST", f"/api/v1/moderation/suspended/{author['id']}/reactivate",
                tenant=tenant, token=vecinos[3]["token"])
    check("un vecino no puede reactivar (403)", s == 403, f"{s} {r}")
    s, r = http(BASE, "POST", f"/api/v1/moderation/suspended/{uuid.uuid4()}/reactivate",
                tenant=tenant, token=admin)
    check("reactivar una cuenta que no existe da 404", s == 404, f"{s} {r}")
    s, r = http(BASE, "POST", f"/api/v1/moderation/suspended/{author['id']}/reactivate",
                tenant=tenant, token=admin)
    check("el jefe del barrio la reactiva", s == 200, f"{s} {r}")
    s, r = http(BASE, "POST", "/api/v1/auth/login",
                {"email": author["email"], "password": author["password"]})
    check("después puede volver a ingresar", s == 200, f"{s} {r}")
    token = r.get("access_token") if s == 200 else author["token"]

    # Los reportes viejos ya no cuentan: un reporte nuevo no la vuelve a suspender.
    p3 = new_post({**author, "token": token}, tenant, "Tercera publicación")
    report(vecinos[3], tenant, p3)
    s, r = http(BASE, "GET", "/api/v1/auth/me", token=token)
    check("tras reactivar, hace falta juntar 3 reportes NUEVOS", s == 200, f"{s} {r}")

    # Seguridad: el celular no puede tocar los campos que decide el servidor.
    sneaky = register(BASE, hood["join_code"], "VECINO", "Vecino tramposo")
    s, r = push(sneaky, "users", {
        "id": sneaky["id"], "full_name": "Vecino tramposo", "home_lat": -5.19, "home_lng": -80.63,
        "email_verified": True, "reports_reset_at": "2099-01-01T00:00:00Z",
        "google_sub": "sub-de-otra-persona", "is_suspended": False, "role": "ADMIN_BARRIO"}, tenant)
    s, me = http(BASE, "GET", "/api/v1/auth/me", token=sneaky["token"])
    check("sync no puede marcar el correo como verificado ni cambiar el rol",
          s == 200 and me["email_verified"] is False and me["role"] == "VECINO", f"{s} {me}")
    p4 = new_post(sneaky, tenant, "Publicación tramposa")
    for v in vecinos[:3]:
        report(v, tenant, p4)
    s, r = http(BASE, "GET", "/api/v1/auth/me", token=sneaky["token"])
    check("sync no puede blindarse contra la suspensión (reports_reset_at)", s == 401, f"{s} {r}")

    print(f"\n{sum(results)}/{len(results)} pruebas OK")
    return 0 if all(results) else 1


if __name__ == "__main__":
    sys.exit(main())
