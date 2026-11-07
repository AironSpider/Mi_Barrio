import uuid
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.core.database import get_db_session
from app.core.tenant_middleware import get_current_principal, get_current_tenant_id
from app.features.proximity_services.models import LocalService, NeighborEndorsement
from app.features.proximity_services.schemas import (
    LocalServiceCreate,
    LocalServiceResponse,
    NeighborEndorsementCreate,
)
from app.features.proximity_services.service import (
    rating_avg_by_service,
    rating_avg_subquery,
    recalculate_service_rating,
)

router = APIRouter(prefix="/api/v1/services", tags=["Proximity Services"])


def _to_response(service: LocalService, rating_avg: float | None) -> dict:
    data = {c.name: getattr(service, c.name) for c in service.__table__.columns}
    data["rating_avg"] = None if rating_avg is None else round(float(rating_avg), 1)
    return data


@router.post("", response_model=LocalServiceResponse, status_code=status.HTTP_201_CREATED)
async def create_service(
    payload: LocalServiceCreate,
    tenant_uuid: uuid.UUID = Depends(get_current_tenant_id),
    principal: dict = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db_session),
):
    if principal["role"] != "COMERCIANTE":
        raise HTTPException(status_code=403, detail="Solo un comerciante puede ofrecer servicios")
    provider_id = uuid.UUID(principal["sub"])
    if payload.provider_user_id != provider_id:
        raise HTTPException(status_code=403, detail="No puedes publicar servicios a nombre de otro usuario")
    new_service = LocalService(
        tenant_id=tenant_uuid,
        provider_user_id=provider_id,
        category=payload.category,
        title=payload.title,
        description=payload.description,
        is_available_in_emergency=payload.is_available_in_emergency,
        lat=payload.lat,
        lng=payload.lng,
        publisher_type=payload.publisher_type,
        publisher_name=payload.publisher_name,
    )
    db.add(new_service)
    await db.commit()
    await db.refresh(new_service)
    return _to_response(new_service, None)

@router.get("", response_model=list[LocalServiceResponse])
async def list_services(
    tenant_uuid: uuid.UUID = Depends(get_current_tenant_id),
    category: str | None = Query(None),
    emergency_only: bool = Query(False),
    db: AsyncSession = Depends(get_db_session),
):
    """Oficios del barrio con su promedio de estrellas.
    Orden: mejor promedio → más calificaciones → más recientes."""
    avg = rating_avg_subquery(tenant_uuid)
    stmt = (
        select(LocalService, avg.c.rating_avg)
        .outerjoin(avg, avg.c.service_id == LocalService.id)
        .where(
            LocalService.tenant_id == tenant_uuid,
            LocalService.is_deleted.is_(False),
        )
    )

    if category:
        stmt = stmt.where(LocalService.category == category)
    if emergency_only:
        stmt = stmt.where(LocalService.is_available_in_emergency.is_(True))

    stmt = stmt.order_by(
        avg.c.rating_avg.desc().nulls_last(),
        LocalService.endorsements_count.desc(),
        LocalService.created_at.desc(),
    )
    result = await db.execute(stmt)
    return [_to_response(service, rating) for service, rating in result.all()]

@router.post("/endorse", status_code=status.HTTP_200_OK)
async def endorse_service(
    payload: NeighborEndorsementCreate,
    tenant_uuid: uuid.UUID = Depends(get_current_tenant_id),
    principal: dict = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db_session),
):
    """Registra un visto bueno y, opcionalmente, estrellas, comentario y foto.
    Un visto bueno por vecino y servicio: si ya existe, se actualiza (upsert)."""
    stmt_service = select(LocalService).where(
        LocalService.id == payload.service_id,
        LocalService.tenant_id == tenant_uuid,
        LocalService.is_deleted.is_(False),
    )
    result_service = await db.execute(stmt_service)
    service = result_service.scalar_one_or_none()

    if not service:
        raise HTTPException(status_code=404, detail="Servicio no encontrado")
    endorser_id = uuid.UUID(principal["sub"])
    if service.provider_user_id == endorser_id:
        raise HTTPException(status_code=400, detail="No puedes calificar tu propio servicio")

    stmt_endorsement = select(NeighborEndorsement).where(
        NeighborEndorsement.service_id == payload.service_id,
        NeighborEndorsement.endorser_user_id == endorser_id,
    )
    endorsement = (await db.execute(stmt_endorsement)).scalar_one_or_none()

    if endorsement is None:
        endorsement = NeighborEndorsement(
            tenant_id=tenant_uuid,
            service_id=payload.service_id,
            endorser_user_id=endorser_id,
        )
        db.add(endorsement)
    endorsement.rating = payload.rating
    endorsement.short_comment = payload.short_comment
    endorsement.photo_b64 = payload.photo_b64
    endorsement.is_deleted = False

    await db.flush()
    service = await recalculate_service_rating(db, payload.service_id)
    await db.commit()

    averages = await rating_avg_by_service(db, tenant_uuid)
    return {
        "success": True,
        "message": "Calificación registrada",
        "data": {
            "service_id": str(payload.service_id),
            "rating_avg": averages.get(payload.service_id),
            "endorsements_count": service.endorsements_count if service else 0,
        },
    }
