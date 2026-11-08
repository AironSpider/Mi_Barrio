"""Chat general (favores y servicios) + bandeja de mensajes.

Revision ID: c3d4e5f6a7b8
Revises: b2c3d4e5f6a7

- chat_messages reemplaza a favor_messages: la conversación se identifica por
  (tipo, publicación, vecino) y guarda al dueño (autor o comerciante) para
  armar la bandeja "Mis mensajes" sin consultas extra.
- Los mensajes de favores ya enviados se COPIAN tal cual; luego se retira
  favor_messages.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision: str = "c3d4e5f6a7b8"
down_revision: Union[str, Sequence[str], None] = "b2c3d4e5f6a7"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "chat_messages",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("tenant_id", postgresql.UUID(as_uuid=True), nullable=False, index=True),
        sa.Column("is_deleted", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("server_updated_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.func.clock_timestamp()),
        sa.Column("context_type", sa.String(length=20), nullable=False),  # FAVOR | SERVICE
        sa.Column("context_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("owner_user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("neighbor_user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("sender_user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("body", sa.String(length=1000), nullable=False),
        sa.CheckConstraint("context_type IN ('FAVOR', 'SERVICE')", name="ck_chat_context_type"),
    )
    op.create_index("ix_chat_thread", "chat_messages",
                    ["context_type", "context_id", "neighbor_user_id", "created_at"])
    op.create_index("ix_chat_owner", "chat_messages", ["tenant_id", "owner_user_id"])
    op.create_index("ix_chat_neighbor", "chat_messages", ["tenant_id", "neighbor_user_id"])

    op.execute("""
        INSERT INTO chat_messages (id, tenant_id, is_deleted, created_at, updated_at, server_updated_at,
                                   context_type, context_id, owner_user_id, neighbor_user_id,
                                   sender_user_id, body)
        SELECT m.id, m.tenant_id, m.is_deleted, m.created_at, m.updated_at, m.server_updated_at,
               'FAVOR', m.post_id, p.author_user_id, m.neighbor_user_id, m.sender_user_id, m.body
        FROM favor_messages m JOIN solidarity_posts p ON p.id = m.post_id
    """)
    op.drop_index("ix_favor_messages_thread", table_name="favor_messages")
    op.drop_table("favor_messages")


def downgrade() -> None:
    op.create_table(
        "favor_messages",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("tenant_id", postgresql.UUID(as_uuid=True), nullable=False, index=True),
        sa.Column("is_deleted", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("server_updated_at", sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.func.clock_timestamp()),
        sa.Column("post_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("solidarity_posts.id"), nullable=False),
        sa.Column("neighbor_user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("sender_user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("body", sa.String(length=1000), nullable=False),
    )
    op.create_index("ix_favor_messages_thread", "favor_messages", ["post_id", "neighbor_user_id", "created_at"])
    op.execute("""
        INSERT INTO favor_messages (id, tenant_id, is_deleted, created_at, updated_at, server_updated_at,
                                    post_id, neighbor_user_id, sender_user_id, body)
        SELECT id, tenant_id, is_deleted, created_at, updated_at, server_updated_at,
               context_id, neighbor_user_id, sender_user_id, body
        FROM chat_messages WHERE context_type = 'FAVOR'
    """)
    op.drop_table("chat_messages")
