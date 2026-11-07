import uuid

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db_session
from app.core.tenant_middleware import get_current_principal, get_current_tenant_id
from app.features.auth_barrio.models import User
from app.features.auth_barrio.schemas import UserProfileResponse

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
