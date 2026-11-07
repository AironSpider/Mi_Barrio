import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db_session
from app.core.tenant_middleware import get_current_principal, get_current_tenant_id
from app.features.auth_barrio.schemas import EmergencyToggleRequest, TenantResponse
from app.features.auth_barrio.service import get_tenant_or_404, set_emergency

router = APIRouter(prefix="/api/v1/tenants", tags=["Barrios (Tenants)"])


@router.get("/current", response_model=TenantResponse)
async def get_current_tenant(
    tenant_uuid: uuid.UUID = Depends(get_current_tenant_id),
    db: AsyncSession = Depends(get_db_session),
):
    """Datos del barrio del header `X-Tenant-ID` (nombre, centro y Modo Emergencia)."""
    return await get_tenant_or_404(db, tenant_uuid)


@router.patch("/emergency-toggle", response_model=TenantResponse)
async def toggle_emergency(
    payload: EmergencyToggleRequest,
    tenant_uuid: uuid.UUID = Depends(get_current_tenant_id),
    principal: dict = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db_session),
):
    """Activa o desactiva el Modo Emergencia para TODO el barrio.

    Los celulares lo reciben en el siguiente pull (`tenant.is_emergency_active`).
    Solo el administrador del barrio (ADMIN_BARRIO) puede hacerlo.
    """
    if principal.get("role") != "ADMIN_BARRIO":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Solo el administrador del barrio puede activar o desactivar la emergencia",
        )
    return await set_emergency(db, tenant_uuid, payload.is_emergency_active)
