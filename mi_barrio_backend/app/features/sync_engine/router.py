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

    posts_stmt = select(SolidarityPost).where(SolidarityPost.tenant_id == tenant_uuid)
    services_stmt = select(LocalService).where(LocalService.tenant_id == tenant_uuid)

    if since:
        try:
            # FIX: Mantener el timezone para que asyncpg lo compare correctamente
            parsed_since = datetime.fromisoformat(since.replace("Z", "+00:00"))
            posts_stmt = posts_stmt.where(SolidarityPost.updated_at > parsed_since)
            services_stmt = services_stmt.where(LocalService.updated_at > parsed_since)
        except ValueError:
            raise HTTPException(status_code=400, detail="Formato de fecha inválido. Usar ISO-8601.")

    posts_results = await db.execute(posts_stmt)
    services_results = await db.execute(services_stmt)

    def serialize(records):
        out = []
        for r in records:
            item = {}
            for col in r.__table__.columns:
                val = getattr(r, col.name)
                if isinstance(val, uuid.UUID):
                    item[col.name] = str(val)
                elif isinstance(val, datetime):
                    item[col.name] = val.isoformat()
                else:
                    item[col.name] = val
            out.append(item)
        return out

    return SyncPullResponse(
        server_timestamp=datetime.now(timezone.utc),
        has_more=False,
        delta={
            "solidarity_posts": serialize(posts_results.scalars().all()),
            "local_services": serialize(services_results.scalars().all()),
        },
    )