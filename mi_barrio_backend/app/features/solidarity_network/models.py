from sqlalchemy import String, Float, Boolean, Text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column
from app.core.database import Base
from app.shared.base_model import BarrioBaseMixin
import uuid

class SolidarityPost(Base, BarrioBaseMixin):
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