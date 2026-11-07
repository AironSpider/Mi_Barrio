import uuid
from datetime import datetime, timezone
from fastapi import APIRouter, Depends, Header, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.core.database import get_db_session
from app.features.proximity_services.models import LocalService, NeighborEndorsement
from app.features.proximity_services.schemas import (
    LocalServiceCreate,
    LocalServiceResponse,
    NeighborEndorsementCreate,
)

router = APIRouter(prefix="/api/v1/services", tags=["Proximity Services"])

@router.post("", response_model=LocalServiceResponse, status_code=status.HTTP_201_CREATED)
async def create_service(
    payload: LocalServiceCreate,
    x_tenant_id: str = Header(..., alias="X-Tenant-ID"),
    db: AsyncSession = Depends(get_db_session),
):
    try:
        tenant_uuid = uuid.UUID(x_tenant_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="X-Tenant-ID inválido")

    new_service = LocalService(
        tenant_id=tenant_uuid,
        provider_user_id=payload.provider_user_id,
        category=payload.category,
        title=payload.title,
        description=payload.description,
        is_available_in_emergency=payload.is_available_in_emergency,
        lat=payload.lat,
        lng=payload.lng,
    )
    db.add(new_service)
    await db.commit()
    await db.refresh(new_service)
    return new_service

@router.get("", response_model=list[LocalServiceResponse])
async def list_services(
    x_tenant_id: str = Header(..., alias="X-Tenant-ID"),
    category: str | None = Query(None),
    available_in_emergency: bool = Query(False),
    db: AsyncSession = Depends(get_db_session),
):
    try:
        tenant_uuid = uuid.UUID(x_tenant_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="X-Tenant-ID inválido")

    stmt = select(LocalService).where(
        LocalService.tenant_id == tenant_uuid,
        LocalService.is_deleted.is_(False),
    )

    if category:
        stmt = stmt.where(LocalService.category == category)
    if available_in_emergency:
        stmt = stmt.where(LocalService.is_available_in_emergency.is_(True))

    stmt = stmt.order_by(LocalService.endorsements_count.desc())
    result = await db.execute(stmt)
    return result.scalars().all()

@router.post("/endorse", status_code=status.HTTP_201_CREATED)
async def endorse_service(
    payload: NeighborEndorsementCreate,
    x_tenant_id: str = Header(..., alias="X-Tenant-ID"),
    db: AsyncSession = Depends(get_db_session),
):
    try:
        tenant_uuid = uuid.UUID(x_tenant_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="X-Tenant-ID inválido")

    stmt = select(LocalService).where(
        LocalService.id == payload.service_id,
        LocalService.tenant_id == tenant_uuid,
        LocalService.is_deleted.is_(False),
    )
    result = await db.execute(stmt)
    service = result.scalar_one_or_none()

    if not service:
        raise HTTPException(status_code=404, detail="Servicio no encontrado")

    endorsement = NeighborEndorsement(
        tenant_id=tenant_uuid,
        service_id=payload.service_id,
        endorser_user_id=payload.endorser_user_id,
        short_comment=payload.short_comment,
    )
    service.endorsements_count += 1
    service.updated_at = datetime.now(timezone.utc)

    db.add(endorsement)
    await db.commit()
    return {"success": True, "message": "Visto bueno vecinal registrado con éxito"}