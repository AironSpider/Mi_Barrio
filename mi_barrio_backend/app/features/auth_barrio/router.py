"""Barrio de la sesión: datos, código de invitación y Modo Emergencia."""
import uuid

from fastapi import APIRouter, Depends, HTTPException, Path, Request
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core import lookup_limit
from app.core.database import get_db_session
from app.core.tenant_middleware import get_current_tenant_id, require_role
from app.features.auth_barrio.models import Tenant
from app.features.auth_barrio.schemas import (
    EmergencyToggleRequest,
    TenantLookupResponse,
    TenantResponse,
)
from app.features.auth_barrio.service import get_tenant_or_404, set_emergency

router = APIRouter(prefix="/api/v1/tenants", tags=["Barrios (Tenants)"])


@router.get("/by-code/{code}", response_model=TenantLookupResponse)
async def get_tenant_by_code(
    request: Request,
    code: str = Path(..., min_length=3, max_length=20, pattern=r"^[A-Za-z0-9-]+$",
                     examples=["BARRIO-01"]),
    db: AsyncSession = Depends(get_db_session),
):
    """Público (sin sesión): confirma a qué barrio pertenece un código de invitación
    antes de registrarse ("Te vas a unir a: ..."). Solo devuelve nombre y centro;
    limitado a 30 consultas cada 5 minutos por IP para que no se adivinen códigos."""
    lookup_limit.check_and_count(request.client.host if request.client else "desconocido")
    tenant = await db.scalar(select(Tenant).where(Tenant.join_code == code.strip().upper()))
    if tenant is None:
        raise HTTPException(status_code=404, detail="No encontramos un barrio con ese código")
    return tenant


@router.get("/current", response_model=TenantResponse)
async def get_current_tenant(
    tenant_uuid: uuid.UUID = Depends(get_current_tenant_id),
    db: AsyncSession = Depends(get_db_session),
):
    """Datos del barrio del header `X-Tenant-ID` (nombre, centro y Modo Emergencia)."""
    return await get_tenant_or_404(db, tenant_uuid)


@router.get("/invite-code")
async def get_invite_code(
    tenant_uuid: uuid.UUID = Depends(get_current_tenant_id),
    principal: dict = Depends(require_role(["ADMIN_BARRIO"])),
    db: AsyncSession = Depends(get_db_session),
):
    """Código para invitar vecinos al barrio de la sesión."""
    tenant = await get_tenant_or_404(db, tenant_uuid)
    return {"tenant_id": str(tenant.id), "invite_code": tenant.join_code}


@router.patch("/emergency-toggle", response_model=TenantResponse)
async def toggle_emergency(
    payload: EmergencyToggleRequest,
    tenant_uuid: uuid.UUID = Depends(get_current_tenant_id),
    principal: dict = Depends(require_role(["ADMIN_BARRIO"])),
    db: AsyncSession = Depends(get_db_session),
):
    """Activa o desactiva el Modo Emergencia para TODO el barrio.

    Los celulares lo reciben en el siguiente pull (`tenant.is_emergency_active`).
    Solo el administrador del barrio (ADMIN_BARRIO) puede hacerlo.
    """
    return await set_emergency(db, tenant_uuid, payload.is_emergency_active)
