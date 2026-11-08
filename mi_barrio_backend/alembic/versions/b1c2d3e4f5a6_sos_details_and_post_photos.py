"""Pedir ayuda con más datos + varias fotos por favor (aditivo)

- `vulnerable_reports`: other_type_label (tipo "Otro"), people_count,
  has_injured, vulnerable_groups, contact_phone. Todo opcional.
- `solidarity_posts.photos`: hasta 4 fotos (la primera sigue en photo_b64).

Revision ID: b1c2d3e4f5a6
Revises: a9b8c7d6e5f4
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "b1c2d3e4f5a6"
down_revision: Union[str, Sequence[str], None] = "a9b8c7d6e5f4"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("vulnerable_reports", sa.Column("other_type_label", sa.String(30), nullable=True))
    op.add_column("vulnerable_reports", sa.Column("people_count", sa.SmallInteger(), nullable=True))
    op.add_column("vulnerable_reports", sa.Column("has_injured", sa.Boolean(), nullable=True))
    op.add_column("vulnerable_reports", sa.Column("vulnerable_groups", sa.String(120), nullable=True))
    op.add_column("vulnerable_reports", sa.Column("contact_phone", sa.String(20), nullable=True))
    op.add_column("solidarity_posts", sa.Column("photos", postgresql.JSONB(), nullable=True))


def downgrade() -> None:
    op.drop_column("solidarity_posts", "photos")
    for col in ("contact_phone", "vulnerable_groups", "has_injured", "people_count", "other_type_label"):
        op.drop_column("vulnerable_reports", col)
