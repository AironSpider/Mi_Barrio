import logging
import uuid
from datetime import datetime, timedelta, timezone
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import func, select, update

from app.features.sync_engine.schemas import SyncPushRequest
from app.features.auth_barrio.models import User
from app.features.solidarity_network.models import SolidarityPost
from app.features.proximity_services.models import LocalService, NeighborEndorsement
from app.features.proximity_services.service import recalculate_service_rating
from app.features.emergency_support.models import VulnerableReport
from app.features.moderation.models import ContentReport
from app.features.moderation import service as moderation
from app.features.sync_engine.validation import validate_payload

logger = logging.getLogger("mi_barrio.sync")

TABLE_MODEL_MAP = {
    "solidarity_posts": SolidarityPost,
    "users": User,
    "local_services": LocalService,
    "neighbor_endorsements": NeighborEndorsement,
    "vulnerable_reports": VulnerableReport,
    # Reportes de publicaciones: solo subida (nunca bajan a otros celulares).
    "content_reports": ContentReport,
}

# Campos que el celular nunca puede escribir: los controla el servidor.
PROTECTED_FIELDS = {
    "id",
    "tenant_id",
    "created_at",
    "updated_at",
    "endorsements_count",
    "rating_avg",
    "is_approved",
    "provider_reply",
    "replied_at",
    "role",
    "server_updated_at",
    "email",
    "password_hash",
    "coordinator_user_id",  # lo pone el servidor al coordinar
    "is_under_review",  # lo decide la moderación (3 reportes / administrador)
}

# Dueño de cada tabla: solo él puede crear o modificar sus registros.
OWNER_FIELD = {
    SolidarityPost: "author_user_id",
    LocalService: "provider_user_id",
    NeighborEndorsement: "endorser_user_id",
    VulnerableReport: "reporter_user_id",
    ContentReport: "reporter_user_id",
}

# Campos que no cambian después de crear el registro (autoría y relación).
IMMUTABLE_ON_UPDATE = {
    "author_user_id", "provider_user_id", "endorser_user_id", "reporter_user_id",
    "service_id", "target_id", "target_type",
}

# Un celular con la fecha mal configurada (ej. 2099) no puede "congelar" registros.
MAX_CLOCK_SKEW = timedelta(minutes=5)


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
    elif model_class is ContentReport:
        # Un reporte por vecino y publicación, aunque el id difiera.
        query = select(ContentReport).where(
            ContentReport.tenant_id == tenant_uuid,
            ContentReport.target_id == _coerce("target_id", payload.get("target_id")),
            ContentReport.reporter_user_id == _coerce("reporter_user_id", payload.get("reporter_user_id")),
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



def _aware(value: datetime) -> datetime:
    """Fechas guardadas sin zona se tratan como UTC."""
    return value if value.tzinfo is not None else value.replace(tzinfo=timezone.utc)


def _client_time(value) -> datetime:
    """Hora del celular para Last-Write-Wins, nunca más allá de ahora + 5 minutos."""
    now = datetime.now(timezone.utc)
    if not value:
        return now
    if not isinstance(value, str):
        raise ValueError("updated_at debe ser una fecha ISO-8601")
    parsed = _aware(datetime.fromisoformat(value.replace("Z", "+00:00")))
    return min(parsed, now + MAX_CLOCK_SKEW)


def _payload_value_matches(payload_value, stored_value) -> bool:
    if isinstance(stored_value, uuid.UUID):
        if isinstance(payload_value, str):
            try:
                payload_value = uuid.UUID(payload_value)
            except ValueError:
                return False
        return payload_value == stored_value
    if isinstance(stored_value, datetime):
        if not isinstance(payload_value, str):
            return False
        try:
            parsed = datetime.fromisoformat(payload_value.replace("Z", "+00:00"))
        except ValueError:
            return False
        return _aware(parsed) == _aware(stored_value)
    return payload_value == stored_value


async def _apply_solidarity_coordination(
    rec_id: uuid.UUID,
    tenant_uuid: uuid.UUID,
    payload: dict,
    operation: str,
    principal_id: uuid.UUID,
    db: AsyncSession,
) -> None:
    post = (await db.execute(
        select(SolidarityPost).where(
            SolidarityPost.id == rec_id,
            SolidarityPost.tenant_id == tenant_uuid,
            SolidarityPost.is_deleted.is_(False),
        ).with_for_update()
    )).scalar_one_or_none()
    if post is None:
        raise ValueError("publicación no encontrada en este barrio")
    if post.author_user_id == principal_id:
        raise ValueError("la coordinación solo está disponible para otra persona")
    if operation != "UPSERT" or payload.get("status") != "EN_COORDINACION":
        raise ValueError("solo puedes coordinar una publicación ajena")
    if payload.get("author_user_id") is None or _coerce(
        "author_user_id", payload["author_user_id"]
    ) != post.author_user_id:
        raise ValueError("no puedes cambiar la autoría de una publicación")
    if post.status not in ("DISPONIBLE", "EN_COORDINACION"):
        raise ValueError("esta publicación ya no está disponible para coordinar")

    columns = {column.name for column in post.__table__.columns}
    # La foto y el coordinador no los decide quien coordina: no se comparan.
    ignored_fields = {"status", "updated_at", "photo_b64", "coordinator_user_id"}
    for key, value in payload.items():
        if key in ignored_fields:
            continue
        if key not in columns or not _payload_value_matches(value, getattr(post, key)):
            raise ValueError(
                f"solo puedes cambiar el estado a EN_COORDINACION: {key} no coincide"
            )

    post.status = "EN_COORDINACION"
    post.coordinator_user_id = principal_id
    post.updated_at = max(_aware(post.updated_at), _client_time(payload.get("updated_at")))


async def _apply_help_offer(
    rec_id: uuid.UUID,
    tenant_uuid: uuid.UUID,
    payload: dict,
    principal_id: uuid.UUID,
    db: AsyncSession,
) -> None:
    """Un vecino que NO es el autor del SOS solo puede decir "voy en camino"."""
    report = (await db.execute(
        select(VulnerableReport).where(
            VulnerableReport.id == rec_id,
            VulnerableReport.tenant_id == tenant_uuid,
            VulnerableReport.is_deleted.is_(False),
        )
    )).scalar_one_or_none()
    if report is None:
        raise ValueError("no puedes crear un pedido de ayuda a nombre de otro vecino")
    helper = _coerce("helper_user_id", payload.get("helper_user_id"))
    if payload.get("status") != "VECINOS_EN_CAMINO" or helper != principal_id:
        raise ValueError("solo puedes marcar que vas en camino a ayudar")
    if report.status == "ATENDIDO":
        raise ValueError("este pedido ya fue atendido")
    report.status = "VECINOS_EN_CAMINO"
    report.helper_user_id = principal_id
    report.updated_at = max(_aware(report.updated_at), _client_time(payload.get("updated_at")))


async def process_sync_push(
    tenant_uuid: uuid.UUID,
    request: SyncPushRequest,
    db: AsyncSession,
    *,
    principal_id: uuid.UUID,
    principal_role: str,
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
    reported_targets: set[tuple[str, uuid.UUID]] = set()
    merchant_profile_changed = False

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
                validate_payload(table_name, payload)
                owner_field = OWNER_FIELD.get(model_class)
                existing_record = await _find_existing(model_class, rec_id, tenant_uuid, payload, db)

                if model_class is SolidarityPost:
                    if (
                        existing_record is not None
                        and existing_record.author_user_id != principal_id
                    ):
                        await _apply_solidarity_coordination(
                            rec_id,
                            tenant_uuid,
                            payload,
                            item.operation,
                            principal_id,
                            db,
                        )
                        await db.flush()
                        processed_ids.append(rec_id_str)
                        continue

                # Caso especial: un vecino ofrece ayuda en el SOS de OTRO vecino.
                # Solo puede marcar VECINOS_EN_CAMINO y ponerse a sí mismo como helper.
                if (
                    model_class is VulnerableReport
                    and _coerce(owner_field, payload.get(owner_field)) != principal_id
                ):
                    await _apply_help_offer(rec_id, tenant_uuid, payload, principal_id, db)
                    await db.flush()
                    processed_ids.append(rec_id_str)
                    continue

                if owner_field and _coerce(owner_field, payload.get(owner_field)) != principal_id:
                    raise ValueError("la mutación no pertenece al usuario autenticado")
                if model_class is User and rec_id != principal_id:
                    raise ValueError("no puedes sincronizar el perfil de otro usuario")
                # Vecinos y comerciantes publican servicios (el rol solo suma la
                # gestión del negocio). Las cuentas de administración no publican.
                if model_class is LocalService and principal_role not in ("VECINO", "COMERCIANTE"):
                    raise ValueError("solo vecinos y comerciantes publican servicios")
                if model_class is LocalService:
                    provider = await db.get(User, principal_id)
                    if provider is None or provider.is_deleted:
                        raise ValueError("la cuenta ya no está activa")
                if model_class is ContentReport:
                    if existing_record is not None:
                        # Ya estaba reportada por este vecino: no se repite ni se edita.
                        await db.flush()
                        processed_ids.append(rec_id_str)
                        continue
                    await moderation.validate_new_report(db, payload, tenant_uuid, principal_id)
                    payload = {**payload, "status": "PENDIENTE"}
                    reported_targets.add(
                        (payload["target_type"], _coerce("target_id", payload["target_id"]))
                    )
                if model_class is NeighborEndorsement:
                    touched_services.add(await _validate_endorsement(payload, tenant_uuid, db))

                # El dueño se verifica también en el registro GUARDADO, no solo en el payload:
                # así nadie edita ni borra lo de otro diciendo "el autor soy yo".
                if (
                    existing_record is not None
                    and owner_field
                    and getattr(existing_record, owner_field) != principal_id
                ):
                    raise ValueError("no puedes modificar un registro de otro usuario")
                if existing_record is None and model_class is not NeighborEndorsement:
                    # El id ya existe en OTRO barrio: nunca se sobrescribe (aislamiento multi-tenant).
                    taken = await db.scalar(select(model_class.id).where(model_class.id == rec_id))
                    if taken is not None:
                        raise ValueError("este id ya pertenece a otro barrio; genera un UUID nuevo")

                client_updated_at = _client_time(payload.get("updated_at"))

                if existing_record:
                    # Last-Write-Wins: solo sobreescribimos si el celular tiene un dato más nuevo
                    if _aware(existing_record.updated_at) <= client_updated_at:
                        for key, val in payload.items():
                            if (
                                hasattr(existing_record, key)
                                and key not in PROTECTED_FIELDS
                                and key not in IMMUTABLE_ON_UPDATE
                            ):
                                setattr(existing_record, key, _coerce(key, val))
                        existing_record.updated_at = client_updated_at
                        # El autor vuelve a "Disponible": ya nadie lo está ayudando.
                        if (
                            model_class is SolidarityPost
                            and payload.get("status") == "DISPONIBLE"
                        ):
                            existing_record.coordinator_user_id = None
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
        if model_class is User:
            merchant_profile_changed = True

    # El promedio y la cantidad de calificaciones los recalcula siempre el servidor.
    for service_id in touched_services:
        await recalculate_service_rating(db, service_id)

    # 3 reportes de vecinos distintos: la publicación pasa a revisión.
    needs_admin = False
    for target_type, target_id in reported_targets:
        if await moderation.apply_review_threshold(db, tenant_uuid, target_type, target_id):
            needs_admin = True

    # Si quien ofrece servicios cambió su perfil (teléfono/WhatsApp), sus servicios
    # vuelven a bajar en el próximo pull con el contacto nuevo (si no tiene, no cambia nada).
    if merchant_profile_changed:
        await db.execute(
            update(LocalService)
            .where(LocalService.tenant_id == tenant_uuid, LocalService.provider_user_id == principal_id)
            .values(server_updated_at=func.clock_timestamp())
        )

    await db.commit()
    if needs_admin:
        await moderation.notify_admins(db, tenant_uuid)
    return processed_ids, rejected
