"""support_groups: grupos de apoyo del barrio (aditivo)

Revision ID: f4a5b6c7d8e9
Revises: e3f4a5b6c7d8
Create Date: 2026-11-07 18:00:00

Sprint 8 (Dev 1):
- Tabla `support_groups` (con server_updated_at para el pull).
- 3 grupos de demostración en el barrio demo de Piura (idempotente).
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision: str = "f4a5b6c7d8e9"
down_revision: Union[str, Sequence[str], None] = "e3f4a5b6c7d8"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

DEMO_TENANT_ID = "a1b2c3d4-e5f6-4a8b-9c0d-1e2f3a4b5c6d"
DEMO_GROUPS = [
    ("5a1c0e2b-0001-4c3d-8e9f-0a1b2c3d4e01", "Brigada de primeros auxilios", "PRIMEROS_AUXILIOS",
     "Vecinos con curso de primeros auxilios y botiquín.", "Losa deportiva", -5.1940, -80.6320),
    ("5a1c0e2b-0002-4c3d-8e9f-0a1b2c3d4e02", "Albergue parroquial", "ALBERGUE",
     "Espacio techado para familias con vivienda afectada.", "Parroquia del barrio", -5.1958, -80.6341),
    ("5a1c0e2b-0003-4c3d-8e9f-0a1b2c3d4e03", "Olla común Mi Barrio", "ALIMENTOS",
     "Almuerzo diario para adultos mayores y familias afectadas.", "Comedor popular", -5.1932, -80.6352),
]


def upgrade() -> None:
    op.create_table(
        "support_groups",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("tenant_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("name", sa.String(length=120), nullable=False),
        sa.Column("group_type", sa.String(length=30), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("contact_phone", sa.String(length=20), nullable=True),
        sa.Column("meeting_point", sa.String(length=200), nullable=True),
        sa.Column("lat", sa.Float(), nullable=True),
        sa.Column("lng", sa.Float(), nullable=True),
        sa.Column("coordinator_user_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("is_deleted", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("server_updated_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text("clock_timestamp()")),
    )
    op.create_index("ix_support_groups_tenant_id", "support_groups", ["tenant_id"])
    op.create_index("ix_support_groups_tenant_server_updated", "support_groups",
                    ["tenant_id", "server_updated_at"])

    for gid, name, gtype, desc, point, lat, lng in DEMO_GROUPS:
        op.execute(sa.text(
            "INSERT INTO support_groups (id, tenant_id, name, group_type, description, meeting_point, lat, lng) "
            "SELECT CAST(:id AS uuid), CAST(:tenant AS uuid), :name, :gtype, :desc, :point, :lat, :lng "
            "WHERE EXISTS (SELECT 1 FROM tenants WHERE id = CAST(:tenant AS uuid)) "
            "ON CONFLICT (id) DO NOTHING"
        ).bindparams(id=gid, tenant=DEMO_TENANT_ID, name=name, gtype=gtype, desc=desc,
                     point=point, lat=lat, lng=lng))


def downgrade() -> None:
    op.drop_index("ix_support_groups_tenant_server_updated", table_name="support_groups")
    op.drop_index("ix_support_groups_tenant_id", table_name="support_groups")
    op.drop_table("support_groups")
