"""Tabla de mensajes del chat entre vecinos (por favor o por servicio)."""
import uuid

from sqlalchemy import CheckConstraint, String
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base
from app.shared.base_model import BarrioBaseMixin


class ChatMessage(Base, BarrioBaseMixin):
    """Mensaje de una conversación sobre un favor o un servicio.

    Conversación = (tipo, publicación, vecino que escribe al dueño).
    El dueño es el autor del favor o el comerciante del servicio.
    """
    __tablename__ = "chat_messages"
    __table_args__ = (
        CheckConstraint("context_type IN ('FAVOR', 'SERVICE')", name="ck_chat_context_type"),
    )

    context_type: Mapped[str] = mapped_column(String(20), nullable=False)
    context_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    owner_user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    neighbor_user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    sender_user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    body: Mapped[str] = mapped_column(String(1000), nullable=False)
