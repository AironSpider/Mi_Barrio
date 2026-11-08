"""Oculta del barrio demo (BARRIO-01) los datos que dejaron pruebas antiguas.

Uso (con la misma DATABASE_URL que el servidor):
    venv\\Scripts\\python.exe scripts\\limpiar_datos_prueba.py            # solo muestra qué haría
    venv\\Scripts\\python.exe scripts\\limpiar_datos_prueba.py --aplicar  # lo aplica

Es un borrado LÓGICO (is_deleted = true): nada se elimina físicamente y se puede
revertir. Solo toca registros con marcas claras de prueba.
"""
import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

from sqlalchemy import text  # noqa: E402

from app.core.database import engine  # noqa: E402

DEMO = "a1b2c3d4-e5f6-4a8b-9c0d-1e2f3a4b5c6d"

RULES = {
    "solidarity_posts": ("title", [
        "Checkpoint 1%", "[SMOKE]%", "E2E%", "Creado offline hace 3 horas", "Editado",
        "Publicado suplantando%", "Prueba checkpoint%",
    ]),
    "local_services": ("title", ["E2E%", "[SMOKE]%"]),
    "vulnerable_reports": ("description", ["[SMOKE]%", "E2E%", "Adulto mayor solo", "Señora con dolor%"]),
    "users": ("full_name", ["Vecina E2E", "Usuario de prueba", "Vecino de prueba", "Cuenta de verificación", "Comerciante E2E%"]),
}


async def main(apply: bool) -> None:
    async with engine.begin() as conn:
        total = 0
        for table, (column, patterns) in RULES.items():
            where = " OR ".join(f"{column} LIKE :p{i}" for i in range(len(patterns)))
            params = {f"p{i}": p for i, p in enumerate(patterns)} | {"t": DEMO}
            sql_where = f"tenant_id = :t AND is_deleted = false AND ({where})"
            count = (await conn.execute(text(f"SELECT count(*) FROM {table} WHERE {sql_where}"), params)).scalar()
            total += count
            print(f"{table}: {count} registro(s) de prueba")
            if apply and count:
                await conn.execute(
                    text(f"UPDATE {table} SET is_deleted = true, server_updated_at = clock_timestamp() WHERE {sql_where}"),
                    params,
                )
        # Calificaciones de servicios que quedaron ocultos.
        orphan_sql = (
            "FROM neighbor_endorsements e JOIN local_services s ON s.id = e.service_id "
            "WHERE e.tenant_id = :t AND e.is_deleted = false AND s.is_deleted = true"
        )
        orphans = (await conn.execute(text(f"SELECT count(*) {orphan_sql}"), {"t": DEMO})).scalar()
        print(f"neighbor_endorsements (de servicios ocultos): {orphans}")
        if apply and orphans:
            await conn.execute(text(
                "UPDATE neighbor_endorsements SET is_deleted = true, server_updated_at = clock_timestamp() "
                "WHERE id IN (SELECT e.id " + orphan_sql + ")"), {"t": DEMO})
        total += orphans
        if not apply:
            await conn.rollback()
    await engine.dispose()
    print(("\nOcultados: " if apply else "\nSe ocultarían: ") + str(total) +
          ("" if apply else "  (usa --aplicar para hacerlo)"))


if __name__ == "__main__":
    asyncio.run(main("--aplicar" in sys.argv))
