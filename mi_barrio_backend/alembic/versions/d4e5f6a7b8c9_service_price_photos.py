"""Servicios: precio y fotos (aditivo).

Revision ID: d4e5f6a7b8c9
Revises: c3d4e5f6a7b8

- local_services.price_text: precio en texto libre ("S/ 30 la visita", "A tratar").
- local_services.photos: hasta 4 fotos (JPEG comprimido en base64). No viajan
  en el pull: se piden aparte en GET /services/{id}/photos.
Los rubros nuevos no necesitan cambios en la base (category es texto).
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision: str = "d4e5f6a7b8c9"
down_revision: Union[str, Sequence[str], None] = "c3d4e5f6a7b8"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("local_services", sa.Column("price_text", sa.String(length=60), nullable=True))
    op.add_column("local_services", sa.Column("photos", postgresql.JSONB(), nullable=True))


def downgrade() -> None:
    op.drop_column("local_services", "photos")
    op.drop_column("local_services", "price_text")
