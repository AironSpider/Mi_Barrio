"""Tablas del muro de apoyo: favores, comentarios y calificaciones."""
import uuid

from sqlalchemy import Boolean, CheckConstraint, Float, ForeignKey, SmallInteger, String, Text, UniqueConstraint
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base
from app.shared.base_model import BarrioBaseMixin


class SolidarityPost(Base, BarrioBaseMixin):
    """Un favor del muro de apoyo: pido u ofrezco ayuda, con modalidad, fotos, ubicación y estado."""
    __tablename__ = "solidarity_posts"

    author_user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    flow_type: Mapped[str] = mapped_column(String(30), nullable=False)      # SOLICITO_AYUDA / OFREZCO_AYUDA
    modality: Mapped[str] = mapped_column(String(50), nullable=False)       # PRESTAMO_HERRAMIENTA, etc.
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    is_emergency_context: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    status: Mapped[str] = mapped_column(String(30), default="DISPONIBLE", nullable=False)
    lat: Mapped[float] = mapped_column(Float, nullable=False)
    lng: Mapped[float] = mapped_column(Float, nullable=False)
    # Foto opcional (JPEG comprimido en base64). No viaja en el pull: se pide aparte.
    photo_b64: Mapped[str | None] = mapped_column(Text, nullable=True)
    # Hasta 4 fotos (la primera también queda en photo_b64 para apps viejas).
    photos: Mapped[list[str] | None] = mapped_column(JSONB, nullable=True)
    # Quién está ayudando: lo pone el servidor al coordinar (para las reseñas).
    coordinator_user_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), nullable=True)
    # true = 3 vecinos lo reportaron: oculto hasta que el administrador lo revise.
    is_under_review: Mapped[bool] = mapped_column(
        Boolean, default=False, server_default="false", nullable=False
    )


class PostComment(Base, BarrioBaseMixin):
    """Comentario público de un vecino en un favor."""
    __tablename__ = "post_comments"

    post_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("solidarity_posts.id"), nullable=False)
    author_user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    body: Mapped[str] = mapped_column(String(500), nullable=False)


class FavorReview(Base, BarrioBaseMixin):
    """Reseña al completar un favor: el autor califica a quien ayudó y viceversa."""
    __tablename__ = "favor_reviews"
    __table_args__ = (
        UniqueConstraint("post_id", "reviewer_user_id", name="uq_favor_review_once"),
        CheckConstraint("rating >= 1 AND rating <= 5", name="ck_favor_review_rating"),
    )

    post_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("solidarity_posts.id"), nullable=False)
    reviewer_user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    reviewed_user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    rating: Mapped[int] = mapped_column(SmallInteger, nullable=False)
    comment: Mapped[str | None] = mapped_column(String(300), nullable=True)
