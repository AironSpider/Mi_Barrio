import uuid

from fastapi import HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from app.features.auth_barrio.models import Tenant


async def get_tenant_or_404(db: AsyncSession, tenant_id: uuid.UUID) -> Tenant:
    tenant = await db.get(Tenant, tenant_id)
    if tenant is None:
        raise HTTPException(
            status_code=404,
            detail="Barrio no registrado. Ejecuta `alembic upgrade head` (crea el barrio demo).",
        )
    return tenant


async def set_emergency(db: AsyncSession, tenant_id: uuid.UUID, active: bool) -> Tenant:
    tenant = await get_tenant_or_404(db, tenant_id)
    tenant.is_emergency_active = active
    await db.commit()
    await db.refresh(tenant)
    return tenant
