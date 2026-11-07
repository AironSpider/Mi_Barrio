from fastapi import APIRouter, Depends, Header, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from datetime import datetime, timezone
import uuid

from app.core.database import get_db_session
from app.features.sync_engine.schemas import SyncPushRequest, SyncPushResponse, SyncPullResponse
from app.features.sync_engine.service import process_sync_push
from app.features.solidarity_network.models import SolidarityPost
from app.features.proximity_services.models import LocalService

router = APIRouter(prefix="/api/v1/sync", tags=["Sync Engine"])

@router.post("/push", response_model=SyncPushResponse)
async def push_offline_mutations(
    request: SyncPushRequest,
    x_tenant_id: str = Header(..., alias="X-Tenant-ID"),
    db: AsyncSession = Depends(get_db_session),
):
    try:
        tenant_uuid = uuid.UUID(x_tenant_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="X-Tenant-ID inválido")

    # Delegamos el trabajo pesado al servicio que acabamos de crear
    processed_ids = await process_sync_push(tenant_uuid, request, db)

    return SyncPushResponse(
        success=True,
        processed_count=len(processed_ids),
        server_timestamp=datetime.now(timezone.utc),
        processed_record_ids=processed_ids,
    )

@router.get("/pull", response_model=SyncPullResponse)
async def pull_delta(
    since: str | None = Query(default=None, description="Timestamp ISO-8601 UTC"),
    x_tenant_id: str = Header(..., alias="X-Tenant-ID"),
    db: AsyncSession = Depends(get_db_session),
):
    try:
        tenant_uuid = uuid.UUID(x_tenant_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="X-Tenant-ID inválido")

    # Consultamos las tablas filtrando por el barrio actual
    posts_stmt = select(SolidarityPost).where(SolidarityPost.tenant_id == tenant_uuid)
    services_stmt = select(LocalService).where(LocalService.tenant_id == tenant_uuid)
    
    if since:
        try:
            parsed_since = datetime.fromisoformat(since.replace("Z", "+00:00"))
            posts_stmt = posts_stmt.where(SolidarityPost.updated_at > parsed_since)
            services_stmt = services_stmt.where(LocalService.updated_at > parsed_since)
        except ValueError:
            raise HTTPException(status_code=400, detail="Formato de fecha inválido.")

    posts_results = await db.execute(posts_stmt)
    services_results = await db.execute(services_stmt)

    # Serialización manual rápida para evitar errores de validación de Pydantic con SQLAlchemy
    def serialize_records(records):
        return [
            {**{c.name: getattr(r, c.name) for c in r.__table__.columns}, 
             "id": str(r.id), "tenant_id": str(r.tenant_id), 
             "updated_at": r.updated_at.isoformat()}
            for r in records
        ]

    return SyncPullResponse(
        server_timestamp=datetime.now(timezone.utc),
        has_more=False,
        delta={
            "solidarity_posts": serialize_records(posts_results.scalars().all()),
            "local_services": serialize_records(services_results.scalars().all()),
        },
    )