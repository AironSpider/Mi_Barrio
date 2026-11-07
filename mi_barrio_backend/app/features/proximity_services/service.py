"""Lógica de calificaciones con estrellas (compartida por el router y el sync)."""
import uuid
from datetime import datetime, timezone

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.features.proximity_services.models import LocalService, NeighborEndorsement


def _rated(tenant_id: uuid.UUID):
    """Filtro común: calificaciones vigentes con estrellas del barrio."""
    return (
        NeighborEndorsement.tenant_id == tenant_id,
        NeighborEndorsement.is_deleted.is_(False),
        NeighborEndorsement.rating.is_not(None),
    )


def rating_avg_subquery(tenant_id: uuid.UUID):
    """Subconsulta (service_id, rating_avg) para unir con local_services."""
    return (
        select(
            NeighborEndorsement.service_id.label("service_id"),
            func.avg(NeighborEndorsement.rating).label("rating_avg"),
        )
        .where(*_rated(tenant_id))
        .group_by(NeighborEndorsement.service_id)
        .subquery()
    )


async def rating_avg_by_service(db: AsyncSession, tenant_id: uuid.UUID) -> dict[uuid.UUID, float]:
    """Promedio de estrellas por servicio del barrio (1 decimal)."""
    sq = rating_avg_subquery(tenant_id)
    rows = (await db.execute(select(sq.c.service_id, sq.c.rating_avg))).all()
    return {sid: round(float(avg), 1) for sid, avg in rows}


async def recalculate_service_rating(db: AsyncSession, service_id: uuid.UUID) -> LocalService | None:
    """Actualiza endorsements_count (= cantidad de calificaciones con estrellas)
    y marca el servicio como modificado para que el pull lleve el nuevo promedio."""
    service = await db.get(LocalService, service_id)
    if service is None:
        return None
    count = await db.scalar(
        select(func.count())
        .select_from(NeighborEndorsement)
        .where(NeighborEndorsement.service_id == service_id, *_rated(service.tenant_id))
    )
    service.endorsements_count = int(count or 0)
    service.updated_at = datetime.now(timezone.utc)
    return service
