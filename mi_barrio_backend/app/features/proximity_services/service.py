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


async def provider_contacts(
    db: AsyncSession, tenant_id: uuid.UUID, provider_ids: set[uuid.UUID]
) -> dict[uuid.UUID, dict]:
    """Teléfono y WhatsApp de quien OFRECE un servicio en el barrio.

    Solo se consulta a dueños de servicios publicados (dato de negocio que
    cargaron para que los contacten), de cuentas activas y aprobadas por la junta.
    """
    if not provider_ids:
        return {}
    from app.features.auth_barrio.models import User  # evita import circular

    rows = (await db.execute(
        select(User.id, User.phone, User.whatsapp).where(
            User.id.in_(provider_ids),
            User.tenant_id == tenant_id,
            User.is_deleted.is_(False),
            User.is_approved.is_(True),
        )
    )).all()
    return {
        uid: {"contact_phone": phone or None, "contact_whatsapp": whatsapp or None}
        for uid, phone, whatsapp in rows
    }


async def recalculate_service_rating(db: AsyncSession, service_id: uuid.UUID) -> LocalService | None:
    """Actualiza el total de vistos buenos y marca el servicio para el pull.

    El promedio solo considera opiniones con estrellas; el contador también
    incluye vistos buenos sin calificación, que son válidos en el cliente.
    """
    service = await db.get(LocalService, service_id)
    if service is None:
        return None
    count = await db.scalar(
        select(func.count())
        .select_from(NeighborEndorsement)
        .where(
            NeighborEndorsement.service_id == service_id,
            NeighborEndorsement.tenant_id == service.tenant_id,
            NeighborEndorsement.is_deleted.is_(False),
        )
    )
    service.endorsements_count = int(count or 0)
    service.updated_at = datetime.now(timezone.utc)
    return service
