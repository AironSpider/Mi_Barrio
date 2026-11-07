import uuid
from datetime import datetime
from sqlalchemy import (
    String, Float, Boolean, Text, Integer, SmallInteger, ForeignKey,
    UniqueConstraint, CheckConstraint, DateTime,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column
from app.core.database import Base
from app.shared.base_model import BarrioBaseMixin

class LocalService(Base, BarrioBaseMixin):
    __tablename__ = "local_services"

    provider_user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    category: Mapped[str] = mapped_column(String(50), nullable=False)
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    description: Mapped[str] = mapped_column(Text, nullable=False)
    is_available_in_emergency: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    # Cantidad de calificaciones con estrellas (lo calcula el servidor).
    endorsements_count: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    lat: Mapped[float] = mapped_column(Float, nullable=False)
    lng: Mapped[float] = mapped_column(Float, nullable=False)
    # Perfil de publicador (v3, aditivo).
    publisher_type: Mapped[str | None] = mapped_column(String(30), nullable=True)
    publisher_name: Mapped[str | None] = mapped_column(String(120), nullable=True)

class NeighborEndorsement(Base, BarrioBaseMixin):
    __tablename__ = "neighbor_endorsements"

    service_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("local_services.id"), nullable=False)
    endorser_user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    short_comment: Mapped[str | None] = mapped_column(String(255), nullable=True)
    # Estrellas 1 a 5 (null = sin estrellas) y foto opcional (v3, aditivo).
    rating: Mapped[int | None] = mapped_column(SmallInteger, nullable=True)
    photo_b64: Mapped[str | None] = mapped_column(Text, nullable=True)
    provider_reply: Mapped[str | None] = mapped_column(Text, nullable=True)
    replied_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    # FIX: Evitar vistos buenos duplicados
    __table_args__ = (
        UniqueConstraint("service_id", "endorser_user_id", name="uix_service_endorser"),
        CheckConstraint("rating IS NULL OR (rating >= 1 AND rating <= 5)",
                        name="ck_endorsement_rating_range"),
    )
