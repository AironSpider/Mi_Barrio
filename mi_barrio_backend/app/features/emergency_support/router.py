import uuid
from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.core.database import get_db_session
# AQUÍ ESTÁ EL IMPORT QUE FALTABA
from app.core.tenant_middleware import get_current_principal, get_current_tenant_id

from app.features.emergency_support.models import SupportGroup, VulnerableReport
from app.features.emergency_support.schemas import (
    SupportGroupCreate,
    SupportGroupResponse,
    VulnerableReportCreate,
    VulnerableReportResponse,
)
from app.shared.contract_values import SupportGroupType
from app.shared.geo_utils import haversine_km

router = APIRouter(prefix="/api/v1/emergency", tags=["Emergency Support"])

@router.post("/sos", response_model=VulnerableReportResponse, status_code=status.HTTP_201_CREATED)
async def report_vulnerability(
    payload: VulnerableReportCreate,
    tenant_uuid: uuid.UUID = Depends(get_current_tenant_id),
    principal: dict = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db_session),
):
    reporter_id = uuid.UUID(principal["sub"])
    if payload.reporter_user_id != reporter_id:
        raise HTTPException(status_code=403, detail="No puedes registrar un reporte a nombre de otro usuario")
    new_report = VulnerableReport(
        tenant_id=tenant_uuid,
        reporter_user_id=reporter_id,
        urgency_level=payload.urgency_level,
        vulnerability_type=payload.vulnerability_type,
        description=payload.description,
        lat=payload.lat,
        lng=payload.lng,
        status=payload.status,
    )
    db.add(new_report)
    await db.commit()
    await db.refresh(new_report)
    return new_report

@router.get("/board", response_model=list[VulnerableReportResponse])
async def list_emergency_board(
    tenant_uuid: uuid.UUID = Depends(get_current_tenant_id),
    urgency_level: str | None = Query(None),
    status_filter: str | None = Query(None),
    db: AsyncSession = Depends(get_db_session),
):
    stmt = select(VulnerableReport).where(
        VulnerableReport.tenant_id == tenant_uuid,
        VulnerableReport.is_deleted.is_(False),
    )

    if urgency_level:
        stmt = stmt.where(VulnerableReport.urgency_level == urgency_level)
    if status_filter:
        stmt = stmt.where(VulnerableReport.status == status_filter)

    stmt = stmt.order_by(VulnerableReport.created_at.desc())
    result = await db.execute(stmt)
    return result.scalars().all()

@router.patch("/{report_id}/attend", response_model=VulnerableReportResponse)
async def attend_emergency_report(
    report_id: uuid.UUID,
    tenant_uuid: uuid.UUID = Depends(get_current_tenant_id),
    principal: dict = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db_session),
):
    stmt = select(VulnerableReport).where(
        VulnerableReport.id == report_id,
        VulnerableReport.tenant_id == tenant_uuid,
        VulnerableReport.is_deleted.is_(False),
    )
    result = await db.execute(stmt)
    report = result.scalar_one_or_none()

    if not report:
        raise HTTPException(status_code=404, detail="Reporte no encontrado")

    report.status = "VECINOS_EN_CAMINO"
    report.helper_user_id = uuid.UUID(principal["sub"])
    report.updated_at = datetime.now(timezone.utc)
    
    await db.commit()
    await db.refresh(report)
    return report

@router.get("/support-groups", response_model=list[SupportGroupResponse])
async def list_support_groups(
    tenant_uuid: uuid.UUID = Depends(get_current_tenant_id),
    group_type: SupportGroupType | None = Query(None),
    lat: float | None = Query(None, ge=-90, le=90, description="Tu ubicación, para ordenar por cercanía"),
    lng: float | None = Query(None, ge=-180, le=180),
    db: AsyncSession = Depends(get_db_session),
):
    """Grupos de apoyo activos del barrio. Con `lat` y `lng`, del más cercano al más lejano
    (los que no tienen ubicación van al final); sin ellos, por nombre."""
    if (lat is None) != (lng is None):
        raise HTTPException(status_code=422, detail="Envía lat y lng juntos")

    stmt = select(SupportGroup).where(
        SupportGroup.tenant_id == tenant_uuid,
        SupportGroup.is_deleted.is_(False),
        SupportGroup.is_active.is_(True),
    )
    if group_type:
        stmt = stmt.where(SupportGroup.group_type == group_type)
    groups = (await db.execute(stmt.order_by(SupportGroup.name))).scalars().all()

    items = [SupportGroupResponse.model_validate(g) for g in groups]
    if lat is not None:
        for item in items:
            if item.lat is not None and item.lng is not None:
                item.distance_km = round(haversine_km(lat, lng, item.lat, item.lng), 2)
        items.sort(key=lambda i: (i.distance_km is None, i.distance_km or 0))
    return items


@router.post("/support-groups", response_model=SupportGroupResponse, status_code=status.HTTP_201_CREATED)
async def create_support_group(
    payload: SupportGroupCreate,
    tenant_uuid: uuid.UUID = Depends(get_current_tenant_id),
    principal: dict = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db_session),
):
    """Registra un grupo de apoyo. Solo el administrador del barrio (ADMIN_BARRIO)."""
    if principal.get("role") != "ADMIN_BARRIO":
        raise HTTPException(status_code=403, detail="Solo el administrador del barrio registra grupos de apoyo")
    if (payload.lat is None) != (payload.lng is None):
        raise HTTPException(status_code=422, detail="Envía lat y lng juntos")
    group = SupportGroup(tenant_id=tenant_uuid, **payload.model_dump())
    db.add(group)
    await db.commit()
    await db.refresh(group)
    return group
