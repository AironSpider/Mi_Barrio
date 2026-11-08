"""support_groups: grupos de apoyo del barrio (aditivo)

Revision ID: f4a5b6c7d8e9
Revises: e3f4a5b6c7d8
Create Date: 2026-11-07 18:00:00

Sprint 8 (Dev 1):
- Tabla `support_groups` (con server_updated_at para el pull).
- (Antes agregaba 3 grupos de demostración; ya no: la base arranca vacía y
  los grupos los crea la junta vecinal. Ver scripts/seed_demo.py.)
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision: str = "f4a5b6c7d8e9"
down_revision: Union[str, Sequence[str], None] = "e3f4a5b6c7d8"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


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


def downgrade() -> None:
    op.drop_index("ix_support_groups_tenant_server_updated", table_name="support_groups")
    op.drop_index("ix_support_groups_tenant_id", table_name="support_groups")
    op.drop_table("support_groups")
