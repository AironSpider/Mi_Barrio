"""Los comerciantes ya no esperan la aprobación de la junta.

Revision ID: b2c3d4e5f6a7
Revises: a1f2e3d4c5b6

Los que estaban en espera quedan activos (los rechazados siguen borrados).
La columna users.is_approved se conserva (siempre true) para no romper las
apps instaladas que aún la leen.
"""
from typing import Sequence, Union

from alembic import op


revision: str = "b2c3d4e5f6a7"
down_revision: Union[str, Sequence[str], None] = "a1f2e3d4c5b6"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute("UPDATE users SET is_approved = true WHERE is_approved = false AND is_deleted = false")


def downgrade() -> None:
    # No se puede saber quién estaba pendiente antes: no se revierte.
    pass
