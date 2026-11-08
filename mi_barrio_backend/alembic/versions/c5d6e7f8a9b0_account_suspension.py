"""Suspensión de cuentas por reportes (aditivo)

Revision ID: c5d6e7f8a9b0
Revises: b1c2d3e4f5a6
Create Date: 2026-11-08 22:00:00

- users.is_suspended: con reportes de 3 vecinos distintos sobre sus
  publicaciones, la cuenta queda suspendida hasta que el jefe del barrio
  (ADMIN_BARRIO) la reactive.
- users.suspended_at: cuándo se suspendió (lo ve el jefe del barrio).
- users.reports_reset_at: al reactivar, los reportes anteriores ya no cuentan
  para una nueva suspensión.
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "c5d6e7f8a9b0"
down_revision: Union[str, Sequence[str], None] = "b1c2d3e4f5a6"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("users", sa.Column("is_suspended", sa.Boolean(), nullable=False, server_default=sa.false()))
    op.add_column("users", sa.Column("suspended_at", sa.DateTime(timezone=True), nullable=True))
    op.add_column("users", sa.Column("reports_reset_at", sa.DateTime(timezone=True), nullable=True))


def downgrade() -> None:
    op.drop_column("users", "reports_reset_at")
    op.drop_column("users", "suspended_at")
    op.drop_column("users", "is_suspended")
