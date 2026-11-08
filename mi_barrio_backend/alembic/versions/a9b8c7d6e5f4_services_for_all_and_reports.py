"""Servicios Necesito/Ofrezco + reportes de publicaciones (aditivo)

- `local_services.flow_type`: OFREZCO_AYUDA (por defecto) o SOLICITO_AYUDA.
- `is_under_review` en servicios y favores: 3 reportes de vecinos distintos
  la ocultan hasta que el administrador decida.
- Tabla `content_reports` (un reporte por vecino y publicación).

Revision ID: a9b8c7d6e5f4
Revises: f9e8d7c6b5a4
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "a9b8c7d6e5f4"
down_revision: Union[str, Sequence[str], None] = "f9e8d7c6b5a4"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "local_services",
        sa.Column("flow_type", sa.String(30), nullable=False, server_default="OFREZCO_AYUDA"),
    )
    for table in ("local_services", "solidarity_posts"):
        op.add_column(
            table,
            sa.Column("is_under_review", sa.Boolean(), nullable=False, server_default=sa.false()),
        )

    op.create_table(
        "content_reports",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("tenant_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("reporter_user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("target_type", sa.String(30), nullable=False),
        sa.Column("target_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("reason", sa.String(30), nullable=False),
        sa.Column("detail", sa.String(300), nullable=True),
        sa.Column("status", sa.String(20), nullable=False, server_default="PENDIENTE"),
        sa.Column("is_deleted", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column(
            "server_updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("clock_timestamp()"),
        ),
        sa.UniqueConstraint("target_id", "reporter_user_id", name="uq_content_report_once"),
    )
    op.create_index("ix_content_reports_tenant_id", "content_reports", ["tenant_id"])
    op.create_index("ix_content_reports_target_id", "content_reports", ["target_id"])
    op.create_index(
        "ix_content_reports_tenant_status", "content_reports", ["tenant_id", "status"]
    )


def downgrade() -> None:
    op.drop_index("ix_content_reports_tenant_status", table_name="content_reports")
    op.drop_index("ix_content_reports_target_id", table_name="content_reports")
    op.drop_index("ix_content_reports_tenant_id", table_name="content_reports")
    op.drop_table("content_reports")
    for table in ("local_services", "solidarity_posts"):
        op.drop_column(table, "is_under_review")
    op.drop_column("local_services", "flow_type")
