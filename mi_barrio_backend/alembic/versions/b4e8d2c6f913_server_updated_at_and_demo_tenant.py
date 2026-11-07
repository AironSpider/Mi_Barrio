"""server_updated_at para el pull + barrio demo (aditivo)

Revision ID: b4e8d2c6f913
Revises: a7c3e91f5b20
Create Date: 2026-11-07 12:00:00

Sprint 6 (Dev 1):
- `server_updated_at` en las tablas sincronizadas. Lo pone SIEMPRE el servidor
  (reloj de PostgreSQL) en cada INSERT/UPDATE. El pull filtra por este campo, así
  un post creado offline y subido horas después sí les llega a los demás.
  (`updated_at` sigue siendo el reloj del celular y se usa solo para Last-Write-Wins).
- Fila del barrio demo en `tenants` (necesaria para el toggle de emergencia).
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'b4e8d2c6f913'
down_revision: Union[str, Sequence[str], None] = 'a7c3e91f5b20'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

SYNCED_TABLES = (
    "solidarity_posts",
    "local_services",
    "neighbor_endorsements",
    "vulnerable_reports",
    "users",
)

DEMO_TENANT_ID = "a1b2c3d4-e5f6-4a8b-9c0d-1e2f3a4b5c6d"


def upgrade() -> None:
    for table in SYNCED_TABLES:
        op.add_column(table, sa.Column("server_updated_at", sa.DateTime(timezone=True), nullable=True))
        # Filas existentes: se toma su updated_at como punto de partida.
        op.execute(f"UPDATE {table} SET server_updated_at = updated_at")
        op.alter_column(
            table,
            "server_updated_at",
            nullable=False,
            server_default=sa.text("clock_timestamp()"),
        )
        op.create_index(
            f"ix_{table}_tenant_server_updated",
            table,
            ["tenant_id", "server_updated_at"],
        )

    # Barrio demo (idempotente: si ya existe o el código está tomado, no hace nada).
    op.execute(
        f"""
        INSERT INTO tenants (id, name, join_code, center_lat, center_lng, is_emergency_active)
        VALUES ('{DEMO_TENANT_ID}', 'Junta Vecinal Demo (Piura)', 'BARRIO-01', -5.1945, -80.6328, false)
        ON CONFLICT DO NOTHING
        """
    )


def downgrade() -> None:
    for table in SYNCED_TABLES:
        op.drop_index(f"ix_{table}_tenant_server_updated", table_name=table)
        op.drop_column(table, "server_updated_at")
    # La fila del barrio demo se conserva (son datos, no esquema).
