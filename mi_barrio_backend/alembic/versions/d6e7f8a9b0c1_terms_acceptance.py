"""Aceptación de términos al crear la cuenta (aditivo)

Revision ID: d6e7f8a9b0c1
Revises: c5d6e7f8a9b0
Create Date: 2026-11-08 23:00:00

- users.terms_accepted_at: cuándo la persona aceptó los Términos, la Política
  de privacidad y las Normas de la comunidad (casilla obligatoria al registrarse).
- users.terms_version: qué versión aceptó (para pedirla de nuevo si cambian).
Las cuentas que ya existían quedan en NULL (no se inventa una aceptación).
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "d6e7f8a9b0c1"
down_revision: Union[str, Sequence[str], None] = "c5d6e7f8a9b0"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("users", sa.Column("terms_accepted_at", sa.DateTime(timezone=True), nullable=True))
    op.add_column("users", sa.Column("terms_version", sa.String(length=20), nullable=True))


def downgrade() -> None:
    op.drop_column("users", "terms_version")
    op.drop_column("users", "terms_accepted_at")
