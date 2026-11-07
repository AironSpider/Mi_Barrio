"""Add merchant approval and merchant review replies.

Revision ID: b7c8d9e0f1a2
Revises: a5b6c7d8e9f1
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "b7c8d9e0f1a2"
down_revision: Union[str, Sequence[str], None] = "a5b6c7d8e9f1"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column(
            "is_approved",
            sa.Boolean(),
            server_default=sa.true(),
            nullable=False,
        ),
    )
    op.add_column("neighbor_endorsements", sa.Column("provider_reply", sa.Text(), nullable=True))
    op.add_column(
        "neighbor_endorsements",
        sa.Column("replied_at", sa.DateTime(timezone=True), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("neighbor_endorsements", "replied_at")
    op.drop_column("neighbor_endorsements", "provider_reply")
    op.drop_column("users", "is_approved")
