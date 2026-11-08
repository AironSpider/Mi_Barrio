"""Cuentas reales: correo verificado, entrar con Google y códigos por correo (aditivo).

Revision ID: f9e8d7c6b5a4
Revises: d4e5f6a7b8c9

- users.email_verified: true para las cuentas que ya existen (no se bloquea a
  nadie); las cuentas nuevas con contraseña empiezan en false.
- users.google_sub: identificador de la cuenta de Google vinculada (único).
- auth_codes: códigos de 6 dígitos para verificar el correo y recuperar la
  contraseña. Solo se guarda su huella (HMAC), nunca el código.
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision: str = "f9e8d7c6b5a4"
down_revision: Union[str, Sequence[str], None] = "d4e5f6a7b8c9"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column("email_verified", sa.Boolean(), nullable=False, server_default=sa.true()),
    )
    op.add_column("users", sa.Column("google_sub", sa.String(length=64), nullable=True))
    op.create_index(
        "ix_users_google_sub_unique",
        "users",
        ["google_sub"],
        unique=True,
        postgresql_where=sa.text("google_sub IS NOT NULL"),
    )
    op.create_table(
        "auth_codes",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("email", sa.String(length=254), nullable=False),
        sa.Column("purpose", sa.String(length=20), nullable=False),
        sa.Column("code_hash", sa.String(length=128), nullable=False),
        sa.Column("attempts", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("used_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.func.now(),
        ),
    )
    op.create_index("ix_auth_codes_email_purpose", "auth_codes", ["email", "purpose"])


def downgrade() -> None:
    op.drop_index("ix_auth_codes_email_purpose", table_name="auth_codes")
    op.drop_table("auth_codes")
    op.drop_index("ix_users_google_sub_unique", table_name="users")
    op.drop_column("users", "google_sub")
    op.drop_column("users", "email_verified")
