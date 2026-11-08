from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import func, select
from datetime import datetime, timedelta, timezone
import uuid

from app.core.database import get_db_session
from app.core.tenant_middleware import get_current_principal, get_current_tenant_id
from app.features.sync_engine.schemas import (
    SyncPullResponse,
    SyncPushRequest,
    SyncPushResponse,
    TenantInfo,
)
from app.features.sync_engine.service import process_sync_push
from app.features.sync_engine.validation import MAX_BATCH
from app.features.auth_barrio.models import Tenant
from app.features.solidarity_network.models import SolidarityPost
from app.features.proximity_services.models import LocalService
from app.features.auth_barrio.service import public_profiles
from app.features.proximity_services.service import provider_contacts, rating_avg_by_service
from app.features.emergency_support.models import SupportGroup, VulnerableReport

router = APIRouter(prefix="/api/v1/sync", tags=["Sync Engine"])

# Margen de seguridad del pull: una escritura que empezó justo antes del pull y se
# confirmó justo después tendría un server_updated_at anterior al cursor. Volver a
# mirar unos segundos atrás evita perderla (los duplicados el celular los ignora).
PULL_SAFETY_MARGIN = timedelta(seconds=30)

# Tablas que baja el pull (todas filtradas por barrio y por server_updated_at).
PULL_MODELS = {
    "solidarity_posts": SolidarityPost,
    "local_services": LocalService,
    "vulnerable_reports": VulnerableReport,
    # Solo bajada: los grupos los registra la junta (POST /emergency/support-groups).
    "support_groups": SupportGroup,
}


def _serialize(record) -> dict:
    item = {}
    for col in record.__table__.columns:
        val = getattr(record, col.name)
        if isinstance(val, uuid.UUID):
            item[col.name] = str(val)
        elif isinstance(val, datetime):
            item[col.name] = val.isoformat()
        else:
            item[col.name] = val
    return item


@router.post("/push", response_model=SyncPushResponse)
async def push_offline_mutations(
    request: SyncPushRequest,
    tenant_uuid: uuid.UUID = Depends(get_current_tenant_id),
    principal: dict = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db_session),
):
    if len(request.mutations) > MAX_BATCH:
        raise HTTPException(
            status_code=413,
            detail=f"Máximo {MAX_BATCH} cambios por envío; el celular debe enviarlos en partes",
        )

    processed_ids, rejected = await process_sync_push(
        tenant_uuid,
        request,
        db,
        principal_id=uuid.UUID(principal["sub"]),
        principal_role=principal["role"],
    )

    return SyncPushResponse(
        success=True,
        processed_count=len(processed_ids),
        server_timestamp=datetime.now(timezone.utc),
        processed_record_ids=processed_ids,
        rejected=rejected,
    )


@router.get("/pull", response_model=SyncPullResponse)
async def pull_delta(
    since: str | None = Query(
        default=None,
        description="Usar el `server_timestamp` del pull anterior (ISO-8601 UTC). Vacío = todo.",
    ),
    tenant_uuid: uuid.UUID = Depends(get_current_tenant_id),
    db: AsyncSession = Depends(get_db_session),
):
    """Cambios del barrio desde el último pull + estado del barrio (Modo Emergencia).

    Filtra por `server_updated_at` (reloj del servidor), no por `updated_at`
    (reloj del celular): así un post creado offline y subido tarde sí aparece.
    """
    cutoff = None
    if since:
        try:
            parsed_since = datetime.fromisoformat(since.replace("Z", "+00:00"))
        except ValueError as exc:
            raise HTTPException(status_code=400, detail="Formato de fecha inválido. Usar ISO-8601.") from exc
        if parsed_since.tzinfo is None:
            parsed_since = parsed_since.replace(tzinfo=timezone.utc)
        cutoff = parsed_since - PULL_SAFETY_MARGIN

    # Cursor tomado del reloj de PostgreSQL ANTES de leer: lo que se escriba
    # mientras tanto llegará en el próximo pull.
    server_now: datetime = await db.scalar(select(func.now()))

    delta: dict[str, list[dict]] = {}
    for name, model in PULL_MODELS.items():
        stmt = select(model).where(model.tenant_id == tenant_uuid)
        if cutoff is not None:
            stmt = stmt.where(model.server_updated_at > cutoff)
        stmt = stmt.order_by(model.server_updated_at)
        delta[name] = [_serialize(r) for r in (await db.execute(stmt)).scalars().all()]

    # El celular guarda el promedio de estrellas ya calculado (sin fotos).
    averages = await rating_avg_by_service(db, tenant_uuid)
    # Y el contacto del comerciante, para que los vecinos puedan llamarlo
    # (antes el detalle buscaba el teléfono en el celular y nunca lo encontraba).
    contacts = await provider_contacts(
        db, tenant_uuid, {uuid.UUID(s["provider_user_id"]) for s in delta["local_services"]}
    )
    for svc in delta["local_services"]:
        # Las fotos se piden aparte (GET /services/{id}/photos).
        svc["photo_count"] = len(svc.pop("photos", None) or [])
        svc["rating_avg"] = averages.get(uuid.UUID(svc["id"]))
        contact = contacts.get(uuid.UUID(svc["provider_user_id"]), {})
        svc["contact_phone"] = contact.get("contact_phone")
        svc["contact_whatsapp"] = contact.get("contact_whatsapp")

    # Favores: sin la foto (se pide aparte), con nombre público y contacto del
    # autor (para WhatsApp / Llamar al coordinar) y el nombre de quien ayuda.
    people = {uuid.UUID(p["author_user_id"]) for p in delta["solidarity_posts"]} | {
        uuid.UUID(p["coordinator_user_id"]) for p in delta["solidarity_posts"] if p.get("coordinator_user_id")
    }
    profiles = await public_profiles(db, tenant_uuid, people)
    for post in delta["solidarity_posts"]:
        post["has_photo"] = bool(post.pop("photo_b64", None))
        author = profiles.get(uuid.UUID(post["author_user_id"]), {})
        post["author_name"] = author.get("name")
        post["contact_phone"] = author.get("contact_phone")
        post["contact_whatsapp"] = author.get("contact_whatsapp")
        coordinator = post.get("coordinator_user_id")
        post["coordinator_name"] = (
            profiles.get(uuid.UUID(coordinator), {}).get("name") if coordinator else None
        )

    tenant = await db.get(Tenant, tenant_uuid)
    tenant_info = TenantInfo(
        id=str(tenant_uuid),
        name=tenant.name if tenant else None,
        is_emergency_active=bool(tenant and tenant.is_emergency_active),
        registered=tenant is not None,
    )

    return SyncPullResponse(
        server_timestamp=server_now.astimezone(timezone.utc),
        has_more=False,
        tenant=tenant_info,
        delta=delta,
    )
