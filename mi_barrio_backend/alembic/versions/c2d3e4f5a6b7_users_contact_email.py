"""Add optional contact email to user profiles.

Revision ID: c2d3e4f5a6b7
Revises: b7c8d9e0f1a2
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "c2d3e4f5a6b7"
down_revision: Union[str, Sequence[str], None] = "b7c8d9e0f1a2"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column("email_contacto", sa.String(length=254), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("users", "email_contacto")
