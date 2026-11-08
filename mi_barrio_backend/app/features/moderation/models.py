import uuid

from sqlalchemy import String, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.database import Base
from app.shared.base_model import BarrioBaseMixin


class ContentReport(Base, BarrioBaseMixin):
    """Reporte de un vecino sobre un favor del muro o un servicio.

    Llega por el sync (funciona sin internet). Con 3 reportes de vecinos
    distintos la publicación pasa a revisión (`is_under_review`) hasta que el
    administrador del barrio o el superadministrador decida.
    """

    __tablename__ = "content_reports"
    __table_args__ = (
        # Un vecino reporta una sola vez cada publicación.
        UniqueConstraint("target_id", "reporter_user_id", name="uq_content_report_once"),
    )

    reporter_user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)
    target_type: Mapped[str] = mapped_column(String(30), nullable=False)  # SOLIDARITY_POST / LOCAL_SERVICE
    target_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False, index=True)
    reason: Mapped[str] = mapped_column(String(30), nullable=False)
    detail: Mapped[str | None] = mapped_column(String(300), nullable=True)
    # PENDIENTE → RESTAURADO (el admin la devolvió) o ELIMINADO (el admin la borró).
    status: Mapped[str] = mapped_column(String(20), default="PENDIENTE", server_default="PENDIENTE", nullable=False)
