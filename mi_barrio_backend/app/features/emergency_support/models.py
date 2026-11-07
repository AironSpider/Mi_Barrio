import uuid
from sqlalchemy import String, Float, Text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column
from app.core.database import Base
from app.shared.base_model import BarrioBaseMixin

class VulnerableReport(Base, BarrioBaseMixin):
    __tablename__ = "vulnerable_reports"

    reporter_user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    urgency_level: Mapped[str] = mapped_column(String(20), nullable=False) # CRITICA, ALTA, MEDIA
    vulnerability_type: Mapped[str] = mapped_column(String(50), nullable=False) 
    description: Mapped[str] = mapped_column(Text, nullable=False)
    lat: Mapped[float] = mapped_column(Float, nullable=False)
    lng: Mapped[float] = mapped_column(Float, nullable=False)
    status: Mapped[str] = mapped_column(String(30), default="PENDIENTE_APOYO", nullable=False)
    helper_user_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), nullable=True)