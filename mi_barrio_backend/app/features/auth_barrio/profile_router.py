"""Perfil propio: ver el perfil completo y borrar la cuenta (derecho de cancelación)."""
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import delete, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db_session
from app.core.tenant_middleware import get_current_principal, get_current_tenant_id
from app.features.auth_barrio.models import AuthCode, Tenant, User
from app.features.chat.models import ChatMessage
from app.features.emergency_support.models import VulnerableReport
from app.features.moderation.models import ContentReport
from app.features.proximity_services.models import LocalService, NeighborEndorsement
from app.features.solidarity_network.models import FavorReview, PostComment, SolidarityPost
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


# Contenido propio que se oculta al borrar la cuenta: (modelo, columna del autor, campos con fotos).
_OWN_CONTENT = (
    (SolidarityPost, "author_user_id", {"photo_b64": None, "photos": None}),
    (LocalService, "provider_user_id", {"photos": None}),
    (PostComment, "author_user_id", {}),
    (NeighborEndorsement, "endorser_user_id", {"photo_b64": None}),
    (FavorReview, "reviewer_user_id", {}),
    (ChatMessage, "sender_user_id", {}),
    (VulnerableReport, "reporter_user_id", {"contact_phone": None}),
    (ContentReport, "reporter_user_id", {}),
)


@router.delete("/me")
async def delete_my_account(
    tenant_uuid: uuid.UUID = Depends(get_current_tenant_id),
    principal: dict = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db_session),
):
    """Borra la cuenta del vecino autenticado (derecho de cancelación, Ley 29733).

    - Sus datos personales se borran (nombre, correo, teléfono, redes, fotos, Google).
    - Su contenido se marca como borrado (is_deleted) para que el pull lo quite de
      todos los celulares del barrio, y se le quitan las fotos.
    - El token deja de servir: el middleware rechaza usuarios borrados.
    - El correo queda libre para crear otra cuenta.
    """
    user_id = uuid.UUID(principal["sub"])
    user = await db.scalar(
        select(User).where(
            User.id == user_id,
            User.tenant_id == tenant_uuid,
            User.is_deleted.is_(False),
        )
    )
    if user is None:
        raise HTTPException(status_code=404, detail="Tu cuenta ya no existe")
    if user.role == "ADMIN_BARRIO":
        raise HTTPException(
            status_code=403,
            detail=(
                "El administrador del barrio no puede borrar su cuenta desde la app. "
                "Escríbenos a mibarrio.app.peru@gmail.com para pasar el cargo a otro vecino."
            ),
        )

    now = datetime.now(timezone.utc)
    for model, owner_column, cleared in _OWN_CONTENT:
        await db.execute(
            update(model)
            .where(
                model.tenant_id == tenant_uuid,
                getattr(model, owner_column) == user_id,
                model.is_deleted.is_(False),
            )
            .values(is_deleted=True, updated_at=now, **cleared)
        )

    if user.email:
        await db.execute(delete(AuthCode).where(AuthCode.email == user.email))

    tenant = await db.get(Tenant, tenant_uuid)
    user.is_deleted = True
    user.full_name = "Cuenta eliminada"
    user.email = None
    user.email_contacto = None
    user.password_hash = None
    user.google_sub = None
    user.phone = ""
    user.whatsapp = None
    user.facebook_url = None
    user.instagram_url = None
    user.photo_b64 = None
    user.address_reference = None
    user.publisher_type = None
    user.publisher_category = None
    user.publisher_name = None
    if tenant is not None:
        user.home_lat = tenant.center_lat
        user.home_lng = tenant.center_lng
    user.updated_at = now
    await db.commit()
    return {"deleted": True, "message": "Tu cuenta y tus datos fueron eliminados."}
