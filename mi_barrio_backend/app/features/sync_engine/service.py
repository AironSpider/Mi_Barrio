import logging
import uuid
from datetime import datetime, timezone
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.features.sync_engine.schemas import SyncPushRequest
from app.features.auth_barrio.models import User
from app.features.solidarity_network.models import SolidarityPost
from app.features.proximity_services.models import LocalService, NeighborEndorsement
from app.features.proximity_services.service import recalculate_service_rating
from app.features.emergency_support.models import VulnerableReport

logger = logging.getLogger("mi_barrio.sync")

TABLE_MODEL_MAP = {
    "solidarity_posts": SolidarityPost,
    "users": User,
    "local_services": LocalService,
    "neighbor_endorsements": NeighborEndorsement,
    "vulnerable_reports": VulnerableReport,
}

# Campos que el celular nunca puede escribir: los controla el servidor.
PROTECTED_FIELDS = {
    "id",
    "tenant_id",
    "created_at",
    "updated_at",
    "endorsements_count",
    "rating_avg",
    "role",
    "server_updated_at",
}


def _coerce(key: str, val):
    """Convierte strings a UUID automáticamente si la columna lo requiere."""
    if key.endswith("_id") and isinstance(val, str):
        try:
            return uuid.UUID(val)
        except ValueError:
            return val
    return val


async def _find_existing(model_class, rec_id: uuid.UUID, tenant_uuid: uuid.UUID, payload: dict, db: AsyncSession):
    """Busca el registro existente. Las calificaciones se buscan por
    (service_id, endorser_user_id): es una por vecino y servicio, aunque el id difiera."""
    if model_class is NeighborEndorsement:
        query = select(NeighborEndorsement).where(
            NeighborEndorsement.tenant_id == tenant_uuid,
            NeighborEndorsement.service_id == _coerce("service_id", payload.get("service_id")),
            NeighborEndorsement.endorser_user_id == _coerce("endorser_user_id", payload.get("endorser_user_id")),
        )
    else:
        query = select(model_class).where(
            model_class.id == rec_id,
            model_class.tenant_id == tenant_uuid,
        )
    return (await db.execute(query)).scalar_one_or_none()


async def _validate_endorsement(payload: dict, tenant_uuid: uuid.UUID, db: AsyncSession) -> uuid.UUID:
    """La calificación debe apuntar a un servicio del mismo barrio y no ser del propio proveedor."""
    service_id = _coerce("service_id", payload.get("service_id"))
    service = (await db.execute(
        select(LocalService).where(LocalService.id == service_id, LocalService.tenant_id == tenant_uuid)
    )).scalar_one_or_none()
    if service is None:
        raise ValueError("servicio no encontrado en este barrio")
    if service.provider_user_id == _coerce("endorser_user_id", payload.get("endorser_user_id")):
        raise ValueError("no se puede calificar el propio servicio")
    return service_id


async def process_sync_push(
    tenant_uuid: uuid.UUID, request: SyncPushRequest, db: AsyncSession
) -> tuple[list[str], list[dict]]:
    """Procesa el lote del celular.

    Cada mutación va en su propio SAVEPOINT: si una falla (dato inválido, servicio
    inexistente, etc.) se descarta solo esa y el resto del lote se guarda igual.
    La que falló no vuelve en processed_record_ids, así que queda en la cola del celular;
    el motivo se informa en `rejected`.
    """
    processed_ids = []
    rejected: list[dict] = []

    def reject(reason: str) -> None:
        rejected.append({"record_id": item.record_id, "target_table": item.target_table, "reason": reason})
    touched_services: set[uuid.UUID] = set()

    for item in request.mutations:
        table_name = item.target_table
        payload = item.payload
        rec_id_str = item.record_id

        try:
            rec_id = uuid.UUID(rec_id_str)
        except ValueError:
            reject("record_id no es un UUID válido")
            continue

        model_class = TABLE_MODEL_MAP.get(table_name)
        if not model_class:
            reject(f"tabla '{table_name}' aún no se sincroniza (soportadas: {', '.join(TABLE_MODEL_MAP)})")
            continue

        try:
            async with db.begin_nested():
                if model_class is NeighborEndorsement:
                    touched_services.add(await _validate_endorsement(payload, tenant_uuid, db))

                existing_record = await _find_existing(model_class, rec_id, tenant_uuid, payload, db)
                if existing_record is None and model_class is not NeighborEndorsement:
                    # El id ya existe en OTRO barrio: nunca se sobrescribe (aislamiento multi-tenant).
                    taken = await db.scalar(select(model_class.id).where(model_class.id == rec_id))
                    if taken is not None:
                        raise ValueError("este id ya pertenece a otro barrio; genera un UUID nuevo")

                client_updated_str = payload.get("updated_at")
                if client_updated_str:
                    client_updated_at = datetime.fromisoformat(client_updated_str.replace("Z", "+00:00"))
                else:
                    client_updated_at = datetime.now(timezone.utc)

                if existing_record:
                    db_updated_at = existing_record.updated_at
                    if db_updated_at.tzinfo is None:
                        db_updated_at = db_updated_at.replace(tzinfo=timezone.utc)

                    # Last-Write-Wins: solo sobreescribimos si el celular tiene un dato más nuevo
                    if db_updated_at <= client_updated_at:
                        for key, val in payload.items():
                            if hasattr(existing_record, key) and key not in PROTECTED_FIELDS:
                                setattr(existing_record, key, _coerce(key, val))
                        existing_record.updated_at = client_updated_at
                else:
                    clean_payload = {
                        "id": rec_id,
                        "tenant_id": tenant_uuid,
                        "updated_at": client_updated_at,
                    }
                    for key, val in payload.items():
                        if hasattr(model_class, key) and key not in PROTECTED_FIELDS:
                            clean_payload[key] = _coerce(key, val)
                    db.add(model_class(**clean_payload))

                # Escribir ya: así un error salta aquí y solo descarta esta mutación.
                await db.flush()
        except Exception as exc:  # noqa: BLE001 - un ítem malo no debe tumbar el lote
            logger.warning("Sync: se descartó %s/%s: %s", table_name, rec_id_str, exc)
            reject(f"{type(exc).__name__}: {exc}"[:200])
            continue

        processed_ids.append(rec_id_str)

    # El promedio y la cantidad de calificaciones los recalcula siempre el servidor.
    for service_id in touched_services:
        await recalculate_service_rating(db, service_id)

    await db.commit()
    return processed_ids, rejected
