"""Moderación vecinal: reportes, revisión automática y decisión del administrador."""
import logging
import uuid
from datetime import datetime, timezone

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.realtime import hub
from app.features.auth_barrio.models import Tenant, User
from app.features.moderation.models import ContentReport
from app.features.proximity_services.models import LocalService
from app.features.solidarity_network.models import SolidarityPost
from app.shared.contract_values import REPORTS_TO_REVIEW

logger = logging.getLogger("mi_barrio.moderation")

TARGET_MODELS = {
    "SOLIDARITY_POST": SolidarityPost,
    "LOCAL_SERVICE": LocalService,
}
_OWNER = {SolidarityPost: "author_user_id", LocalService: "provider_user_id"}


def _coerce_uuid(value) -> uuid.UUID:
    return value if isinstance(value, uuid.UUID) else uuid.UUID(str(value))


async def load_target(db: AsyncSession, target_type: str, target_id, tenant_id: uuid.UUID | None):
    model = TARGET_MODELS.get(target_type)
    if model is None:
        raise ValueError(f"target_type inválido: {target_type!r}")
    conditions = [model.id == _coerce_uuid(target_id)]
    if tenant_id is not None:
        conditions.append(model.tenant_id == tenant_id)
    return await db.scalar(select(model).where(*conditions).with_for_update())


async def validate_new_report(
    db: AsyncSession, payload: dict, tenant_id: uuid.UUID, principal_id: uuid.UUID
) -> None:
    """La publicación existe en el barrio, no es propia y "Otro" trae el motivo escrito."""
    target = await load_target(db, payload.get("target_type"), payload.get("target_id"), tenant_id)
    if target is None or target.is_deleted:
        raise ValueError("la publicación reportada no existe en este barrio")
    if getattr(target, _OWNER[type(target)]) == principal_id:
        raise ValueError("no puedes reportar tu propia publicación")
    if payload.get("reason") == "OTRO" and len((payload.get("detail") or "").strip()) < 3:
        raise ValueError("cuéntanos el motivo del reporte")


async def apply_review_threshold(
    db: AsyncSession, tenant_id: uuid.UUID, target_type: str, target_id: uuid.UUID
) -> bool:
    """Con 3 reportes pendientes de vecinos distintos, la publicación pasa a revisión.
    Devuelve True si acaba de pasar a revisión."""
    reporters = await db.scalar(
        select(func.count(func.distinct(ContentReport.reporter_user_id))).where(
            ContentReport.tenant_id == tenant_id,
            ContentReport.target_id == target_id,
            ContentReport.status == "PENDIENTE",
            ContentReport.is_deleted.is_(False),
        )
    )
    if (reporters or 0) < REPORTS_TO_REVIEW:
        return False
    target = await load_target(db, target_type, target_id, tenant_id)
    if target is None or target.is_deleted or target.is_under_review:
        return False
    target.is_under_review = True
    # Así el pull la vuelve a bajar y los celulares la ocultan.
    target.updated_at = datetime.now(timezone.utc)
    return True


async def notify_admins(db: AsyncSession, tenant_id: uuid.UUID) -> None:
    """Aviso al instante a los administradores del barrio que tengan la app abierta."""
    admins = set(
        (await db.execute(
            select(User.id).where(
                User.tenant_id == tenant_id,
                User.role == "ADMIN_BARRIO",
                User.is_deleted.is_(False),
            )
        )).scalars().all()
    )
    if admins:
        await hub.send(admins, {"type": "moderation.review", "tenant_id": str(tenant_id)})


async def pending_count(db: AsyncSession, tenant_id: uuid.UUID | None) -> int:
    """Cuántas publicaciones tienen reportes sin resolver."""
    stmt = select(func.count(func.distinct(ContentReport.target_id))).where(
        ContentReport.status == "PENDIENTE",
        ContentReport.is_deleted.is_(False),
    )
    if tenant_id is not None:
        stmt = stmt.where(ContentReport.tenant_id == tenant_id)
    return int(await db.scalar(stmt) or 0)


async def list_reported(db: AsyncSession, tenant_id: uuid.UUID | None) -> list[dict]:
    """Publicaciones con reportes pendientes, las que están en revisión primero."""
    stmt = select(ContentReport).where(
        ContentReport.status == "PENDIENTE",
        ContentReport.is_deleted.is_(False),
    )
    if tenant_id is not None:
        stmt = stmt.where(ContentReport.tenant_id == tenant_id)
    reports = (await db.execute(stmt.order_by(ContentReport.created_at.desc()))).scalars().all()

    grouped: dict[uuid.UUID, dict] = {}
    for report in reports:
        item = grouped.setdefault(report.target_id, {
            "target_type": report.target_type,
            "target_id": str(report.target_id),
            "tenant_id": str(report.tenant_id),
            "reports": [],
            "last_reported_at": report.created_at,
        })
        item["reports"].append({"reason": report.reason, "detail": report.detail})

    tenant_names: dict[uuid.UUID, str] = {}
    if tenant_id is None and grouped:
        ids = {uuid.UUID(g["tenant_id"]) for g in grouped.values()}
        tenant_names = dict((await db.execute(select(Tenant.id, Tenant.name).where(Tenant.id.in_(ids)))).all())

    result = []
    for target_id, item in grouped.items():
        model = TARGET_MODELS[item["target_type"]]
        target = await db.get(model, target_id)
        if target is None or target.is_deleted:
            continue
        item.update({
            "title": target.title,
            "description": target.description,
            "is_under_review": bool(target.is_under_review),
            "report_count": len(item["reports"]),
            "tenant_name": tenant_names.get(uuid.UUID(item["tenant_id"])),
        })
        result.append(item)
    result.sort(key=lambda g: (not g["is_under_review"], -g["report_count"]))
    return result


async def resolve(
    db: AsyncSession,
    tenant_id: uuid.UUID | None,
    target_type: str,
    target_id: uuid.UUID,
    action: str,
) -> None:
    """`restore`: vuelve a mostrarse. `remove`: se elimina. Los reportes quedan resueltos."""
    target = await load_target(db, target_type, target_id, tenant_id)
    if target is None:
        raise LookupError("publicación no encontrada")
    if action == "restore":
        target.is_under_review = False
        new_status = "RESTAURADO"
    elif action == "remove":
        target.is_under_review = False
        target.is_deleted = True
        new_status = "ELIMINADO"
    else:
        raise ValueError("acción inválida: usa restore o remove")
    target.updated_at = datetime.now(timezone.utc)
    reports = (await db.execute(
        select(ContentReport).where(
            ContentReport.target_id == target_id,
            ContentReport.status == "PENDIENTE",
        )
    )).scalars().all()
    for report in reports:
        report.status = new_status
        report.updated_at = datetime.now(timezone.utc)
    await db.commit()
    logger.info("Moderación: %s %s/%s", action, target_type, target_id)
