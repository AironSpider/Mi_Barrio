import uuid
from datetime import datetime, timezone
from sqlalchemy import String, Float, Boolean, DateTime, Index, Text, func, text, true
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column
from app.core.database import Base
from app.shared.base_model import BarrioBaseMixin

class Tenant(Base):
    __tablename__ = "tenants"
    
    # Tenant no usa BarrioBaseMixin porque es la tabla padre
    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    join_code: Mapped[str] = mapped_column(String(20), unique=True, index=True, nullable=False)
    center_lat: Mapped[float] = mapped_column(Float, nullable=False)
    center_lng: Mapped[float] = mapped_column(Float, nullable=False)
    is_emergency_active: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)

class User(Base, BarrioBaseMixin):
    __tablename__ = "users"
    __table_args__ = (
        Index("ix_users_email_unique", "email", unique=True),
        Index(
            "uq_users_active_neighborhood_admin",
            "tenant_id",
            unique=True,
            postgresql_where=text(
                "role = 'ADMIN_BARRIO' AND is_deleted = false"
            ),
        ),
    )
    
    # Hereda id, tenant_id, created_at, updated_at e is_deleted de BarrioBaseMixin
    full_name: Mapped[str] = mapped_column(String(150), nullable=False)
    phone: Mapped[str] = mapped_column(String(20), nullable=False)
    address_reference: Mapped[str] = mapped_column(String(200), nullable=True)
    home_lat: Mapped[float] = mapped_column(Float, nullable=False)
    home_lng: Mapped[float] = mapped_column(Float, nullable=False)
    role: Mapped[str] = mapped_column(String(50), default="VECINO", nullable=False)
    is_approved: Mapped[bool] = mapped_column(
        Boolean, default=True, server_default=true(), nullable=False
    )
    tutorial_completed: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    email: Mapped[str | None] = mapped_column(String(254), nullable=True)
    email_contacto: Mapped[str | None] = mapped_column(String(254), nullable=True)
    password_hash: Mapped[str | None] = mapped_column(String(256), nullable=True)
    # Migración B (Sprint 9): redes de contacto y perfil de publicador (todo opcional).
    whatsapp: Mapped[str | None] = mapped_column(String(20), nullable=True)
    facebook_url: Mapped[str | None] = mapped_column(String(300), nullable=True)
    instagram_url: Mapped[str | None] = mapped_column(String(300), nullable=True)
    photo_b64: Mapped[str | None] = mapped_column(Text, nullable=True)
    publisher_type: Mapped[str | None] = mapped_column(String(30), nullable=True)
    publisher_category: Mapped[str | None] = mapped_column(String(50), nullable=True)
    publisher_name: Mapped[str | None] = mapped_column(String(120), nullable=True)


class PlatformAdmin(Base):
    """Cuenta global, fuera de cualquier barrio."""

    __tablename__ = "platform_admins"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    full_name: Mapped[str] = mapped_column(String(150), nullable=False)
    email: Mapped[str] = mapped_column(String(254), unique=True, nullable=False, index=True)
    password_hash: Mapped[str] = mapped_column(String(256), nullable=False)
    is_active: Mapped[bool] = mapped_column(
        Boolean, default=True, server_default=true(), nullable=False
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        server_default=func.now(),
        nullable=False,
    )