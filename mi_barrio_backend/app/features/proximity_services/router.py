import uuid
from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.core.database import get_db_session
from app.core.tenant_middleware import (
    get_current_principal,
    get_current_tenant_id,
    require_role,
)
from app.features.auth_barrio.models import User
from app.features.proximity_services.models import LocalService, NeighborEndorsement
from app.features.proximity_services.schemas import (
    LocalServiceCreate,
    LocalServiceResponse,
    NeighborEndorsementCreate,
    NeighborEndorsementResponse,
    EndorsementPhotoResponse,
    EndorsementReplyRequest,
    ServicePhotosResponse,
)
from app.features.auth_barrio.service import public_profiles
from app.features.proximity_services.service import (
    rating_avg_by_service,
    rating_avg_for_service,
    rating_avg_subquery,
    recalculate_service_rating,
)

router = APIRouter(prefix="/api/v1/services", tags=["Proximity Services"])
endorsement_router = APIRouter(prefix="/api/v1/endorsements", tags=["Proximity Services"])


def _to_response(service: LocalService, rating_avg: float | None) -> dict:
    data = {c.name: getattr(service, c.name) for c in service.__table__.columns}
    data["rating_avg"] = None if rating_avg is None else round(float(rating_avg), 1)
    # Las fotos pesan: la lista solo dice cuántas hay.
    data["photo_count"] = len(data.pop("photos") or [])
    return data


@router.post("", response_model=LocalServiceResponse, status_code=status.HTTP_201_CREATED)
async def create_service(
    payload: LocalServiceCreate,
    tenant_uuid: uuid.UUID = Depends(get_current_tenant_id),
    principal: dict = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db_session),
):
    # Vecinos y comerciantes publican servicios; el rol de comerciante solo
    # agrega la gestión de su negocio.
    if principal["role"] not in ("VECINO", "COMERCIANTE"):
        raise HTTPException(status_code=403, detail="Solo vecinos y comerciantes publican servicios")
    provider_id = uuid.UUID(principal["sub"])
    if payload.provider_user_id != provider_id:
        raise HTTPException(status_code=403, detail="No puedes publicar servicios a nombre de otro usuario")
    provider = await db.get(User, provider_id)
    if provider is None or provider.is_deleted:
        raise HTTPException(status_code=401, detail="La cuenta ya no está activa")
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
        price_text=(payload.price_text or "").strip() or None,
        photos=payload.photos or None,
        flow_type=payload.flow_type,
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
            LocalService.is_under_review.is_(False),
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


@router.get("/mine", response_model=list[LocalServiceResponse])
async def list_my_services(
    tenant_uuid: uuid.UUID = Depends(get_current_tenant_id),
    principal: dict = Depends(require_role(["COMERCIANTE", "VECINO"])),
    db: AsyncSession = Depends(get_db_session),
):
    services = (await db.execute(
        select(LocalService).where(
            LocalService.tenant_id == tenant_uuid,
            LocalService.provider_user_id == uuid.UUID(principal["sub"]),
            LocalService.is_deleted.is_(False),
        ).order_by(LocalService.created_at.desc())
    )).scalars().all()
    averages = await rating_avg_by_service(db, tenant_uuid)
    return [_to_response(service, averages.get(service.id)) for service in services]


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

    return {
        "success": True,
        "message": "Calificación registrada",
        "data": {
            "service_id": str(payload.service_id),
            "rating_avg": await rating_avg_for_service(db, tenant_uuid, payload.service_id),
            "endorsements_count": service.endorsements_count if service else 0,
        },
    }


@router.get("/{service_id}/endorsements", response_model=list[NeighborEndorsementResponse])
async def list_service_endorsements(
    service_id: uuid.UUID,
    tenant_uuid: uuid.UUID = Depends(get_current_tenant_id),
    principal: dict = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db_session),
):
    service = (await db.execute(
        select(LocalService).where(
            LocalService.id == service_id,
            LocalService.tenant_id == tenant_uuid,
            LocalService.is_deleted.is_(False),
        )
    )).scalar_one_or_none()
    if service is None:
        raise HTTPException(status_code=404, detail="Servicio no encontrado")

    endorsements = (await db.execute(
        select(NeighborEndorsement).where(
            NeighborEndorsement.service_id == service_id,
            NeighborEndorsement.tenant_id == tenant_uuid,
            NeighborEndorsement.is_deleted.is_(False),
        ).order_by(NeighborEndorsement.created_at.desc())
    )).scalars().all()
    profiles = await public_profiles(db, tenant_uuid, {e.endorser_user_id for e in endorsements})
    return [
        NeighborEndorsementResponse.model_validate(e).model_copy(
            update={
                "has_photo": e.photo_b64 is not None,
                "endorser_name": profiles.get(e.endorser_user_id, {}).get("name", "Vecino"),
            }
        )
        for e in endorsements
    ]


@router.get("/{service_id}/photos", response_model=ServicePhotosResponse)
async def get_service_photos(
    service_id: uuid.UUID,
    tenant_uuid: uuid.UUID = Depends(get_current_tenant_id),
    db: AsyncSession = Depends(get_db_session),
):
    """Fotos del servicio (aparte, para que la lista y el pull pesen poco)."""
    service = await db.scalar(select(LocalService).where(
        LocalService.id == service_id,
        LocalService.tenant_id == tenant_uuid,
        LocalService.is_deleted.is_(False),
    ))
    if service is None:
        raise HTTPException(status_code=404, detail="Servicio no encontrado")
    return ServicePhotosResponse(id=service.id, photos=list(service.photos or []))


@router.post("/{service_id}/recommendations/{rec_id}/reply", response_model=NeighborEndorsementResponse)
async def reply_to_recommendation(
    service_id: uuid.UUID,
    rec_id: uuid.UUID,
    payload: EndorsementReplyRequest,
    tenant_uuid: uuid.UUID = Depends(get_current_tenant_id),
    principal: dict = Depends(require_role(["COMERCIANTE"])),
    db: AsyncSession = Depends(get_db_session),
):
    service = await db.scalar(select(LocalService).where(
        LocalService.id == service_id,
        LocalService.tenant_id == tenant_uuid,
        LocalService.provider_user_id == uuid.UUID(principal["sub"]),
        LocalService.is_deleted.is_(False),
    ))
    if service is None:
        raise HTTPException(status_code=404, detail="Servicio propio no encontrado")
    endorsement = await db.scalar(select(NeighborEndorsement).where(
        NeighborEndorsement.id == rec_id,
        NeighborEndorsement.service_id == service_id,
        NeighborEndorsement.tenant_id == tenant_uuid,
        NeighborEndorsement.is_deleted.is_(False),
    ))
    if endorsement is None:
        raise HTTPException(status_code=404, detail="Recomendación no encontrada")
    endorsement.provider_reply = payload.reply.strip()
    endorsement.replied_at = datetime.now(timezone.utc)
    endorsement.updated_at = endorsement.replied_at
    await db.commit()
    await db.refresh(endorsement)
    return endorsement


@endorsement_router.get("/{endorsement_id}/photo", response_model=EndorsementPhotoResponse)
async def get_endorsement_photo(
    endorsement_id: uuid.UUID,
    tenant_uuid: uuid.UUID = Depends(get_current_tenant_id),
    principal: dict = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db_session),
):
    endorsement = (await db.execute(
        select(NeighborEndorsement).where(
            NeighborEndorsement.id == endorsement_id,
            NeighborEndorsement.tenant_id == tenant_uuid,
            NeighborEndorsement.is_deleted.is_(False),
        )
    )).scalar_one_or_none()
    if endorsement is None or endorsement.photo_b64 is None:
        raise HTTPException(status_code=404, detail="Foto de calificación no encontrada")

    return {
        "id": endorsement.id,
        "photo_b64": endorsement.photo_b64,
        "content_type": "image/jpeg",
    }
