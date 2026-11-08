import uuid
from sqlalchemy import Boolean, SmallInteger, String, Float, Text
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
    # Datos para decidir a quién ayudar primero (todos opcionales).
    other_type_label: Mapped[str | None] = mapped_column(String(30), nullable=True)  # si el tipo es OTRO
    people_count: Mapped[int | None] = mapped_column(SmallInteger, nullable=True)
    has_injured: Mapped[bool | None] = mapped_column(Boolean, nullable=True)
    vulnerable_groups: Mapped[str | None] = mapped_column(String(120), nullable=True)  # "NINOS,MAYORES"
    contact_phone: Mapped[str | None] = mapped_column(String(20), nullable=True)

class SupportGroup(Base, BarrioBaseMixin):
    """Grupo de apoyo del barrio (brigada, albergue, olla común...). Lo administra la junta."""
    __tablename__ = "support_groups"

    name: Mapped[str] = mapped_column(String(120), nullable=False)
    group_type: Mapped[str] = mapped_column(String(30), nullable=False)  # PRIMEROS_AUXILIOS, RESCATE, etc.
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    contact_phone: Mapped[str | None] = mapped_column(String(20), nullable=True)
    meeting_point: Mapped[str | None] = mapped_column(String(200), nullable=True)
    lat: Mapped[float | None] = mapped_column(Float, nullable=True)
    lng: Mapped[float | None] = mapped_column(Float, nullable=True)
    coordinator_user_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), nullable=True)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)