"""users: redes de contacto y perfil de publicador (migración B, aditiva)

Revision ID: a5b6c7d8e9f1
Revises: f4a5b6c7d8e9
Create Date: 2026-11-07 21:00:00

Sprint 9 (Dev 1): columnas nullable en `users`. La app ya las guardaba en SQLite;
ahora también suben por /sync/push y el vecino las recupera con GET /users/me.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "a5b6c7d8e9f1"
down_revision: Union[str, Sequence[str], None] = "f4a5b6c7d8e9"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None

COLUMNS = (
    ("whatsapp", sa.String(length=20)),
    ("facebook_url", sa.String(length=300)),
    ("instagram_url", sa.String(length=300)),
    ("photo_b64", sa.Text()),
    ("publisher_type", sa.String(length=30)),
    ("publisher_category", sa.String(length=50)),
    ("publisher_name", sa.String(length=120)),
)


def upgrade() -> None:
    for name, type_ in COLUMNS:
        op.add_column("users", sa.Column(name, type_, nullable=True))


def downgrade() -> None:
    for name, _ in reversed(COLUMNS):
        op.drop_column("users", name)
