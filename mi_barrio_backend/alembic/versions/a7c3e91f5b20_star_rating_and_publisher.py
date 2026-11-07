"""star rating, photo and publisher fields (aditivo)

Revision ID: a7c3e91f5b20
Revises: 0c2dd344d0d3
Create Date: 2026-11-07 09:30:00

Cambios aditivos del plan v4 (Sprint 5), todos nullable:
- A. neighbor_endorsements: rating (1 a 5) y photo_b64.
- C. local_services: publisher_type y publisher_name.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'a7c3e91f5b20'
down_revision: Union[str, Sequence[str], None] = '0c2dd344d0d3'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('neighbor_endorsements', sa.Column('rating', sa.SmallInteger(), nullable=True))
    op.add_column('neighbor_endorsements', sa.Column('photo_b64', sa.Text(), nullable=True))
    op.create_check_constraint(
        'ck_endorsement_rating_range',
        'neighbor_endorsements',
        'rating IS NULL OR (rating >= 1 AND rating <= 5)',
    )
    op.add_column('local_services', sa.Column('publisher_type', sa.String(length=30), nullable=True))
    op.add_column('local_services', sa.Column('publisher_name', sa.String(length=120), nullable=True))


def downgrade() -> None:
    op.drop_column('local_services', 'publisher_name')
    op.drop_column('local_services', 'publisher_type')
    op.drop_constraint('ck_endorsement_rating_range', 'neighbor_endorsements', type_='check')
    op.drop_column('neighbor_endorsements', 'photo_b64')
    op.drop_column('neighbor_endorsements', 'rating')
