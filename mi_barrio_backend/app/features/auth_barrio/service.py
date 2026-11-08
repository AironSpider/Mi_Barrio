import uuid

from fastapi import HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.features.auth_barrio.models import Tenant, User


def public_name(full_name: str | None) -> str:
    """Nombre que ven los demás vecinos: nombre + inicial ("Rosa Calle" → "Rosa C.")."""
    parts = (full_name or "").split()
    if not parts:
        return "Vecino"
    return f"{parts[0]} {parts[1][0]}." if len(parts) > 1 else parts[0]


async def public_profiles(
    db: AsyncSession,
    tenant_id: uuid.UUID,
    user_ids: set[uuid.UUID],
    *,
    only_approved: bool = False,
) -> dict[uuid.UUID, dict]:
    """Nombre público y contacto (teléfono / WhatsApp que el vecino cargó en su
    perfil) de cuentas activas del barrio. Nunca correo ni datos de otro barrio."""
    if not user_ids:
        return {}
    conditions = [
        User.id.in_(user_ids),
        User.tenant_id == tenant_id,
        User.is_deleted.is_(False),
    ]
    if only_approved:
        conditions.append(User.is_approved.is_(True))
    rows = (await db.execute(
        select(User.id, User.full_name, User.phone, User.whatsapp).where(*conditions)
    )).all()
    return {
        uid: {
            "name": public_name(name),
            "contact_phone": phone or None,
            "contact_whatsapp": whatsapp or None,
        }
        for uid, name, phone, whatsapp in rows
    }


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
