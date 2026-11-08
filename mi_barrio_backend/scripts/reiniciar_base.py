"""Deja la base de datos VACÍA para empezar desde cero (barrios, vecinos, todo).

⚠ BORRA DE VERDAD y no se puede deshacer. Antes de usarlo en producción,
haz una copia (Neon/Render → Backups) si quieres conservar algo.

Uso (desde mi_barrio_backend, con la DATABASE_URL de la base a limpiar):
    .venv/bin/python scripts/reiniciar_base.py                    # solo muestra qué borraría
    .venv/bin/python scripts/reiniciar_base.py --confirmar NOMBRE_BD
    .venv/bin/python scripts/reiniciar_base.py --confirmar NOMBRE_BD --sin-superadmin

- Sin --confirmar no toca nada: muestra el servidor, la base y cuántas filas
  tiene cada tabla.
- --confirmar pide el NOMBRE de la base (el que muestra el modo de prueba), para
  no borrar la base equivocada por accidente.
- Conserva la estructura (tablas y migraciones) y, salvo --sin-superadmin, la
  cuenta del superadministrador, para que pueda entrar y crear los barrios.
  Con --sin-superadmin, créalo de nuevo con:
      .venv/bin/python -m app.features.auth_barrio.platform_admin_bootstrap

Después: en los celulares de prueba, borra los datos de la app (o reinstálala)
para que no muestren lo guardado antes.
"""
import argparse
import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

from sqlalchemy import text  # noqa: E402
from sqlalchemy.engine import make_url  # noqa: E402

from app.core.database import DATABASE_URL, engine  # noqa: E402

KEEP_ALWAYS = {"alembic_version"}


async def _tables(conn) -> list[str]:
    rows = await conn.execute(text(
        "SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename"
    ))
    return [r[0] for r in rows if r[0] not in KEEP_ALWAYS]


async def main(confirm: str | None, keep_admin: bool) -> int:
    url = make_url(DATABASE_URL)
    print(f"Servidor: {url.host}   Base de datos: {url.database}")
    async with engine.begin() as conn:
        tables = await _tables(conn)
        keep = {"platform_admins"} if keep_admin else set()
        targets = [t for t in tables if t not in keep]
        total = 0
        for table in tables:
            count = (await conn.execute(text(f'SELECT count(*) FROM "{table}"'))).scalar_one()
            mark = "se conserva" if table in keep else "se BORRA"
            print(f"  {table:<28} {count:>7} filas  ({mark})")
            if table in targets:
                total += count

        if confirm is None:
            print(f"\nModo de prueba: no se borró nada ({total} filas se borrarían).")
            print(f"Para borrar: --confirmar {url.database}")
            return 0
        if confirm != url.database:
            print(f"\nNo coincide: escribiste '{confirm}' pero la base es '{url.database}'. No se borró nada.")
            return 1

        quoted = ", ".join(f'"{t}"' for t in targets)
        await conn.execute(text(f"TRUNCATE {quoted} RESTART IDENTITY CASCADE"))
    await engine.dispose()
    print(f"\nListo: se borraron {total} filas. La base quedó vacía"
          + (" (se conservó el superadministrador)." if keep_admin else "."))
    return 0


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--confirmar", metavar="NOMBRE_BD", help="nombre de la base a vaciar")
    parser.add_argument("--sin-superadmin", action="store_true", help="también borra al superadministrador")
    args = parser.parse_args()
    sys.exit(asyncio.run(main(args.confirmar, keep_admin=not args.sin_superadmin)))
