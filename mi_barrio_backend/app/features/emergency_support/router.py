import uuid
from datetime import datetime, timezone
from fastapi import APIRouter, Depends, Header, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.core.database import get_db_session
from app.features.emergency_support.models import VulnerableReport
from app.features.emergency_support.schemas import (
    VulnerableReportCreate,
    VulnerableReportResponse,
)

router = APIRouter(prefix="/api/v1/emergency", tags=["Emergency Support"])

@router.post("/sos", response_model=VulnerableReportResponse, status_code=status.HTTP_201_CREATED)
async def report_vulnerability(
    payload: VulnerableReportCreate,
    x_tenant_id: str = Header(..., alias="X-Tenant-ID"),
    db: AsyncSession = Depends(get_db_session),
):
    try:
        tenant_uuid = uuid.UUID(x_tenant_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="X-Tenant-ID inválido")

    new_report = VulnerableReport(
        tenant_id=tenant_uuid,
        reporter_user_id=payload.reporter_user_id,
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
    x_tenant_id: str = Header(..., alias="X-Tenant-ID"),
    urgency_level: str | None = Query(None),
    status_filter: str | None = Query(None),
    db: AsyncSession = Depends(get_db_session),
):
    try:
        tenant_uuid = uuid.UUID(x_tenant_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="X-Tenant-ID inválido")

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

# ... código existente ...

@router.patch("/{report_id}/attend", response_model=VulnerableReportResponse)
async def attend_emergency_report(
    report_id: uuid.UUID,
    helper_user_id: uuid.UUID = Query(...),
    x_tenant_id: str = Header(..., alias="X-Tenant-ID"),
    db: AsyncSession = Depends(get_db_session),
):
    try:
        tenant_uuid = uuid.UUID(x_tenant_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="X-Tenant-ID inválido")

    stmt = select(VulnerableReport).where(
        VulnerableReport.id == report_id,
        VulnerableReport.tenant_id == tenant_uuid,
        VulnerableReport.is_deleted.is_(False),
    )
    result = await db.execute(stmt)
    report = result.scalar_one_or_none()

    if not report:
        raise HTTPException(status_code=404, detail="Reporte no encontrado")

    # FIX: Ajustado al estado definido en el contrato de la Hackathon
    report.status = "VECINOS_EN_CAMINO"
    report.helper_user_id = helper_user_id
    report.updated_at = datetime.now(timezone.utc)
    
    await db.commit()
    await db.refresh(report)
    return report