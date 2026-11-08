"""Detalle del favor: foto, coordinador, comentarios, reseñas y chat (aditivo).

Revision ID: a1f2e3d4c5b6
Revises: c2d3e4f5a6b7

- solidarity_posts.photo_b64: foto opcional (JPEG comprimido, se pide aparte).
- solidarity_posts.coordinator_user_id: quién está ayudando (para las reseñas).
- post_comments: comentarios públicos de los vecinos en un favor.
- favor_reviews: al completarse, autor y quien ayudó se califican (1 a 5).
- favor_messages: chat en tiempo real entre el autor y cada vecino interesado.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision: str = "a1f2e3d4c5b6"
down_revision: Union[str, Sequence[str], None] = "c2d3e4f5a6b7"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def _base_columns() -> list[sa.Column]:
    return [
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("tenant_id", postgresql.UUID(as_uuid=True), nullable=False, index=True),
        sa.Column("is_deleted", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column(
            "server_updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.clock_timestamp(),
        ),
    ]


def upgrade() -> None:
    op.add_column("solidarity_posts", sa.Column("photo_b64", sa.Text(), nullable=True))
    op.add_column(
        "solidarity_posts",
        sa.Column("coordinator_user_id", postgresql.UUID(as_uuid=True), nullable=True),
    )

    op.create_table(
        "post_comments",
        *_base_columns(),
        sa.Column("post_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("solidarity_posts.id"), nullable=False),
        sa.Column("author_user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("body", sa.String(length=500), nullable=False),
    )
    op.create_index("ix_post_comments_post", "post_comments", ["post_id", "created_at"])

    op.create_table(
        "favor_reviews",
        *_base_columns(),
        sa.Column("post_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("solidarity_posts.id"), nullable=False),
        sa.Column("reviewer_user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("reviewed_user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("rating", sa.SmallInteger(), nullable=False),
        sa.Column("comment", sa.String(length=300), nullable=True),
        sa.UniqueConstraint("post_id", "reviewer_user_id", name="uq_favor_review_once"),
        sa.CheckConstraint("rating >= 1 AND rating <= 5", name="ck_favor_review_rating"),
    )

    op.create_table(
        "favor_messages",
        *_base_columns(),
        sa.Column("post_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("solidarity_posts.id"), nullable=False),
        # Conversación = (favor, vecino que no es el autor).
        sa.Column("neighbor_user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("sender_user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("body", sa.String(length=1000), nullable=False),
    )
    op.create_index("ix_favor_messages_thread", "favor_messages", ["post_id", "neighbor_user_id", "created_at"])


def downgrade() -> None:
    op.drop_index("ix_favor_messages_thread", table_name="favor_messages")
    op.drop_table("favor_messages")
    op.drop_table("favor_reviews")
    op.drop_index("ix_post_comments_post", table_name="post_comments")
    op.drop_table("post_comments")
    op.drop_column("solidarity_posts", "coordinator_user_id")
    op.drop_column("solidarity_posts", "photo_b64")
