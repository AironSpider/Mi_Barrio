import uuid
from sqlalchemy import String, Float, Boolean, Text, Integer, ForeignKey
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column
from app.core.database import Base
from app.shared.base_model import BarrioBaseMixin
from sqlalchemy import String, Float, Boolean, Text, Integer, ForeignKey, UniqueConstraint

class LocalService(Base, BarrioBaseMixin):
    __tablename__ = "local_services"

    provider_user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    category: Mapped[str] = mapped_column(String(50), nullable=False)
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    description: Mapped[str] = mapped_column(Text, nullable=False)
    is_available_in_emergency: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    endorsements_count: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    lat: Mapped[float] = mapped_column(Float, nullable=False)
    lng: Mapped[float] = mapped_column(Float, nullable=False)

class NeighborEndorsement(Base, BarrioBaseMixin):
    __tablename__ = "neighbor_endorsements"

    service_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("local_services.id"), nullable=False)
    endorser_user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    short_comment: Mapped[str | None] = mapped_column(String(255), nullable=True)

    # FIX: Un vecino solo puede avalar un servicio una vez
    __table_args__ = (
        UniqueConstraint("service_id", "endorser_user_id", name="uix_service_endorser"),
    )