"""Allow one active neighborhood administrator per tenant.

Revision ID: e3f4a5b6c7d8
Revises: d2e3f4a5b6c7
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "e3f4a5b6c7d8"
down_revision: Union[str, Sequence[str], None] = "d2e3f4a5b6c7"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_index(
        "uq_users_active_neighborhood_admin",
        "users",
        ["tenant_id"],
        unique=True,
        postgresql_where=sa.text(
            "role = 'ADMIN_BARRIO' AND is_deleted = false"
        ),
    )


def downgrade() -> None:
    op.drop_index(
        "uq_users_active_neighborhood_admin",
        table_name="users",
    )
