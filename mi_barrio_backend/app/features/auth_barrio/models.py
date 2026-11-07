import uuid
from sqlalchemy import String, Float, Boolean
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
    
    # Hereda id, tenant_id, created_at, updated_at e is_deleted de BarrioBaseMixin
    full_name: Mapped[str] = mapped_column(String(150), nullable=False)
    phone: Mapped[str] = mapped_column(String(20), nullable=False)
    address_reference: Mapped[str] = mapped_column(String(200), nullable=True)
    home_lat: Mapped[float] = mapped_column(Float, nullable=False)
    home_lng: Mapped[float] = mapped_column(Float, nullable=False)
    role: Mapped[str] = mapped_column(String(50), default="VECINO", nullable=False)
    tutorial_completed: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)