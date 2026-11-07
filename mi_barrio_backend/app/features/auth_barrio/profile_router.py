import uuid

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db_session
from app.core.tenant_middleware import (
    get_current_principal,
    get_current_tenant_id,
    require_role,
)
from app.features.auth_barrio.models import User
from app.features.auth_barrio.schemas import (
    MerchantApprovalResponse,
    PendingMerchantResponse,
    UserProfileResponse,
)

router = APIRouter(prefix="/api/v1/users", tags=["Perfil del vecino"])


@router.get("/me", response_model=UserProfileResponse)
async def get_my_profile(
    tenant_uuid: uuid.UUID = Depends(get_current_tenant_id),
    principal: dict = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db_session),
):
    """Perfil completo del vecino autenticado (redes y perfil de publicador incluidos).

    La app lo usa para recuperar el perfil en un teléfono nuevo; los cambios suben
    por /sync/push (tabla `users`, solo la fila propia)."""
    user = await db.scalar(
        select(User).where(
            User.id == uuid.UUID(principal["sub"]),
            User.tenant_id == tenant_uuid,
            User.is_deleted.is_(False),
        )
    )
    if user is None:
        raise HTTPException(status_code=404, detail="Perfil no encontrado en este barrio")
    return user


@router.get(
    "/pending-merchants",
    response_model=list[PendingMerchantResponse],
)
async def list_pending_merchants(
    tenant_uuid: uuid.UUID = Depends(get_current_tenant_id),
    principal: dict = Depends(require_role(["ADMIN_BARRIO"])),
    db: AsyncSession = Depends(get_db_session),
):
    return (await db.execute(
        select(User).where(
            User.tenant_id == tenant_uuid,
            User.role == "COMERCIANTE",
            User.is_approved.is_(False),
            User.is_deleted.is_(False),
        ).order_by(User.created_at.asc())
    )).scalars().all()


@router.patch(
    "/{user_id}/approve-merchant",
    response_model=MerchantApprovalResponse,
)
async def approve_merchant(
    user_id: uuid.UUID,
    tenant_uuid: uuid.UUID = Depends(get_current_tenant_id),
    principal: dict = Depends(require_role(["ADMIN_BARRIO"])),
    db: AsyncSession = Depends(get_db_session),
):
    merchant = await db.scalar(select(User).where(
        User.id == user_id,
        User.tenant_id == tenant_uuid,
        User.role == "COMERCIANTE",
        User.is_deleted.is_(False),
    ))
    if merchant is None:
        raise HTTPException(status_code=404, detail="Comerciante no encontrado")
    merchant.is_approved = True
    await db.commit()
    return MerchantApprovalResponse(
        user_id=merchant.id,
        is_approved=True,
        is_deleted=False,
    )


@router.patch(
    "/{user_id}/reject-merchant",
    response_model=MerchantApprovalResponse,
)
async def reject_merchant(
    user_id: uuid.UUID,
    tenant_uuid: uuid.UUID = Depends(get_current_tenant_id),
    principal: dict = Depends(require_role(["ADMIN_BARRIO"])),
    db: AsyncSession = Depends(get_db_session),
):
    merchant = await db.scalar(select(User).where(
        User.id == user_id,
        User.tenant_id == tenant_uuid,
        User.role == "COMERCIANTE",
        User.is_deleted.is_(False),
    ))
    if merchant is None:
        raise HTTPException(status_code=404, detail="Comerciante no encontrado")
    merchant.is_approved = False
    merchant.is_deleted = True
    await db.commit()
    return MerchantApprovalResponse(
        user_id=merchant.id,
        is_approved=False,
        is_deleted=True,
    )
