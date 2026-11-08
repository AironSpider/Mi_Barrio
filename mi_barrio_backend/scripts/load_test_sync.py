"""Prueba de carga simple (Sprint 12, Dev 1): N vecinos sincronizando a la vez.

Uso (con la API levantada):
    venv\\Scripts\\python.exe scripts\\load_test_sync.py [http://127.0.0.1:8000] [--vecinos 20] [--rondas 3]

Crea un barrio de prueba propio (nunca toca BARRIO-01) y N vecinos. En cada
ronda, todos a la vez (barrera) hacen lo mismo que el celular al volver la
señal: push de 5 favores + 1 SOS y luego pull. Al final, cada vecino hace un
pull completo y debe ver TODO lo que subieron los demás (nada se pierde).
"""
import argparse
import statistics
import sys
import threading
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone

from _test_env import http, isolated_neighborhood, register

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

LAT, LNG = -5.1945, -80.6328
POSTS_POR_RONDA = 5
MAX_P95_SEGUNDOS = 5.0


def now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def mutations_for(user_id: str) -> tuple[list[dict], list[str], list[str]]:
    t = now()
    muts, posts, reports = [], [], []
    for i in range(POSTS_POR_RONDA):
        pid = str(uuid.uuid4())
        posts.append(pid)
        muts.append({"target_table": "solidarity_posts", "record_id": pid, "operation": "UPSERT",
                     "payload": {"id": pid, "author_user_id": user_id, "flow_type": "OFREZCO_AYUDA",
                                 "modality": "AYUDA_TEMPORAL", "title": f"Carga {i}",
                                 "is_emergency_context": False, "status": "DISPONIBLE",
                                 "lat": LAT, "lng": LNG, "updated_at": t}})
    rid = str(uuid.uuid4())
    reports.append(rid)
    muts.append({"target_table": "vulnerable_reports", "record_id": rid, "operation": "UPSERT",
                 "payload": {"id": rid, "reporter_user_id": user_id, "urgency_level": "MEDIA",
                             "vulnerability_type": "FALTA_SUMINISTROS", "description": "carga",
                             "lat": LAT, "lng": LNG, "status": "PENDIENTE_APOYO", "updated_at": t}})
    return muts, posts, reports


def main() -> int:
    parser = argparse.ArgumentParser()
    # 127.0.0.1 y no localhost: en Windows localhost prueba IPv6 primero y suma ~2 s por pedido.
    parser.add_argument("base", nargs="?", default="http://127.0.0.1:8000")
    parser.add_argument("--vecinos", type=int, default=20)
    parser.add_argument("--rondas", type=int, default=3)
    args = parser.parse_args()
    base = args.base.rstrip("/")

    s, b = http(base, "GET", "/health")
    if s != 200 or not b.get("success"):
        print(f"FALLA /health en {base}: {s} {b}")
        return 2

    hood = isolated_neighborhood(base, "Prueba de carga")
    tenant = hood["tenant_id"]
    vecinos = [register(base, hood["join_code"], "VECINO", f"Vecino carga {i}")
               for i in range(args.vecinos)]
    print(f"Barrio de prueba listo con {len(vecinos)} vecinos. "
          f"{args.rondas} rondas simultáneas…")

    lock = threading.Lock()
    tiempos: list[float] = []
    errores: list[str] = []
    esperados_posts: set[str] = set()
    esperados_sos: set[str] = set()
    barrera = threading.Barrier(len(vecinos))

    def vecino_sync(v: dict) -> None:
        cursor = None
        for _ in range(args.rondas):
            muts, posts, reports = mutations_for(v["id"])
            barrera.wait()  # todos disparan a la vez
            t0 = time.perf_counter()
            s, b = http(base, "POST", "/api/v1/sync/push",
                        {"client_sync_timestamp": now(), "mutations": muts},
                        tenant=tenant, token=v["token"])
            ok_push = s == 200 and sorted(b.get("processed_record_ids", [])) == sorted(posts + reports)
            query = f"?since={cursor}" if cursor else ""
            s2, b2 = http(base, "GET", "/api/v1/sync/pull" + query, tenant=tenant, token=v["token"])
            dt = time.perf_counter() - t0
            with lock:
                tiempos.append(dt)
                if ok_push:
                    esperados_posts.update(posts)
                    esperados_sos.update(reports)
                else:
                    errores.append(f"push {s}: {str(b)[:200]}")
                if s2 != 200:
                    errores.append(f"pull {s2}: {str(b2)[:200]}")
            if s2 == 200:
                cursor = b2["server_timestamp"]

    inicio = time.perf_counter()
    with ThreadPoolExecutor(max_workers=len(vecinos)) as pool:
        for f in [pool.submit(vecino_sync, v) for v in vecinos]:
            f.result()
    total = time.perf_counter() - inicio

    # Nada se pierde: un pull completo trae todo lo subido.
    s, full = http(base, "GET", "/api/v1/sync/pull", tenant=tenant, token=vecinos[0]["token"])
    vistos_posts = {r["id"] for r in full.get("delta", {}).get("solidarity_posts", [])} if s == 200 else set()
    vistos_sos = {r["id"] for r in full.get("delta", {}).get("vulnerable_reports", [])} if s == 200 else set()
    faltan = len(esperados_posts - vistos_posts) + len(esperados_sos - vistos_sos)
    has_more = full.get("has_more") if s == 200 else None

    tiempos.sort()
    p95 = tiempos[max(0, int(len(tiempos) * 0.95) - 1)] if tiempos else float("inf")
    esperadas = len(vecinos) * args.rondas
    print(f"Sincronizaciones: {len(tiempos)}/{esperadas} en {total:.1f} s")
    if tiempos:
        print(f"Tiempo push+pull: mediana {statistics.median(tiempos):.2f} s · "
              f"p95 {p95:.2f} s · máx {tiempos[-1]:.2f} s")
    print(f"Registros subidos: {len(esperados_posts)} favores + {len(esperados_sos)} SOS · "
          f"faltan en el pull: {faltan}" + (" (pull paginado: has_more)" if has_more else ""))

    checks = [
        ("0 errores HTTP", not errores, "; ".join(errores[:3])),
        ("todas las sincronizaciones respondieron", len(tiempos) == esperadas, ""),
        ("nada se pierde (pull completo trae todo)", s == 200 and faltan == 0, f"{s}, faltan {faltan}"),
        (f"p95 < {MAX_P95_SEGUNDOS:.0f} s", p95 < MAX_P95_SEGUNDOS, f"{p95:.2f} s"),
    ]
    for name, ok, detail in checks:
        print(f"{'OK  ' if ok else 'FALLA'} {name}" + (f"  -> {detail}" if detail and not ok else ""))
    fallas = sum(1 for _, ok, _ in checks if not ok)
    print(f"\n{len(checks) - fallas}/{len(checks)} OK")
    return 1 if fallas else 0


if __name__ == "__main__":
    sys.exit(main())
