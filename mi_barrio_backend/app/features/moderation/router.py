import uuid
from datetime import datetime
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db_session
from app.core.tenant_middleware import get_current_tenant_id, require_role
from app.features.moderation import service
from app.shared.contract_values import ReportTargetType

router = APIRouter(prefix="/api/v1/moderation", tags=["Moderación"])
# Bajo /api/v1/platform/: el middleware solo deja pasar al superadministrador.
platform_router = APIRouter(prefix="/api/v1/platform/reports", tags=["Moderación"])

Action = Literal["restore", "remove"]


class ReportReasonItem(BaseModel):
    reason: str
    detail: str | None = None


class ReportedItem(BaseModel):
    target_type: str
    target_id: str
    tenant_id: str
    tenant_name: str | None = None
    title: str
    description: str | None = None
    is_under_review: bool
    report_count: int
    last_reported_at: datetime
    reports: list[ReportReasonItem]


class PendingCount(BaseModel):
    pending: int


async def _resolve(db, tenant_id, target_type, target_id, action) -> dict:
    try:
        await service.resolve(db, tenant_id, target_type, target_id, action)
    except LookupError as exc:
        raise HTTPException(status_code=404, detail="Publicación no encontrada") from exc
    return {"success": True}


# ── Administrador del barrio ──
@router.get("/reports", response_model=list[ReportedItem])
async def list_reports(
    tenant_uuid: uuid.UUID = Depends(get_current_tenant_id),
    _: dict = Depends(require_role(["ADMIN_BARRIO"])),
    db: AsyncSession = Depends(get_db_session),
):
    """Publicaciones reportadas del barrio (las que están en revisión primero)."""
    return await service.list_reported(db, tenant_uuid)


@router.get("/reports/count", response_model=PendingCount)
async def count_reports(
    tenant_uuid: uuid.UUID = Depends(get_current_tenant_id),
    _: dict = Depends(require_role(["ADMIN_BARRIO"])),
    db: AsyncSession = Depends(get_db_session),
):
    return PendingCount(pending=await service.pending_count(db, tenant_uuid))


@router.post("/reports/{target_type}/{target_id}/{action}")
async def resolve_report(
    target_type: ReportTargetType,
    target_id: uuid.UUID,
    action: Action,
    tenant_uuid: uuid.UUID = Depends(get_current_tenant_id),
    _: dict = Depends(require_role(["ADMIN_BARRIO"])),
    db: AsyncSession = Depends(get_db_session),
):
    """`restore` la vuelve a mostrar; `remove` la elimina."""
    return await _resolve(db, tenant_uuid, target_type, target_id, action)


# ── Superadministrador (todos los barrios) ──
@platform_router.get("", response_model=list[ReportedItem])
async def platform_list_reports(
    _: dict = Depends(require_role(["SUPER_ADMIN"])),
    db: AsyncSession = Depends(get_db_session),
):
    return await service.list_reported(db, None)


@platform_router.get("/count", response_model=PendingCount)
async def platform_count_reports(
    _: dict = Depends(require_role(["SUPER_ADMIN"])),
    db: AsyncSession = Depends(get_db_session),
):
    return PendingCount(pending=await service.pending_count(db, None))


@platform_router.post("/{target_type}/{target_id}/{action}")
async def platform_resolve_report(
    target_type: ReportTargetType,
    target_id: uuid.UUID,
    action: Action,
    _: dict = Depends(require_role(["SUPER_ADMIN"])),
    db: AsyncSession = Depends(get_db_session),
):
    return await _resolve(db, None, target_type, target_id, action)
