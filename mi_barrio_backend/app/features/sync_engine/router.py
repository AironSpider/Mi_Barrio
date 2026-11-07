from fastapi import APIRouter, Depends, Header, HTTPException, Query
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from datetime import datetime, timezone
import uuid

from app.core.database import get_db_session
from app.features.sync_engine.schemas import SyncPushRequest, SyncPushResponse, SyncPullResponse
from app.features.solidarity_network.models import SolidarityPost

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
        raise HTTPException(status_code=400, detail="X-Tenant-ID debe ser un UUID válido")

    processed_ids = []
    
    for item in request.mutations:
        table = item.target_table
        payload = item.payload
        rec_id = uuid.UUID(item.record_id)
        
        if table == "solidarity_posts":
            query = select(SolidarityPost).where(
                SolidarityPost.id == rec_id,
                SolidarityPost.tenant_id == tenant_uuid,
            )
            result = await db.execute(query)
            existing = result.scalar_one_or_none()

            client_updated_at = datetime.fromisoformat(
                payload.get("updated_at", datetime.now(timezone.utc).isoformat())
            )

            if existing:
                # Last-Write-Wins: sólo sobreescribimos si el cambio es posterior
                if existing.updated_at <= client_updated_at:
                    for key, val in payload.items():
                        if hasattr(existing, key) and key not in ["id", "tenant_id", "created_at"]:
                            setattr(existing, key, val)
                    existing.updated_at = client_updated_at
            else:
                new_post = SolidarityPost(
                    id=rec_id,
                    tenant_id=tenant_uuid,
                    author_user_id=uuid.UUID(payload["author_user_id"]),
                    flow_type=payload["flow_type"],
                    modality=payload["modality"],
                    title=payload["title"],
                    description=payload.get("description"),
                    is_emergency_context=payload.get("is_emergency_context", False),
                    status=payload.get("status", "DISPONIBLE"),
                    lat=payload["lat"],
                    lng=payload["lng"],
                    updated_at=client_updated_at,
                )
                db.add(new_post)
            
            processed_ids.append(item.record_id)

    await db.commit()

    return SyncPushResponse(
        success=True,
        processed_count=len(processed_ids),
        server_timestamp=datetime.now(timezone.utc),
        processed_record_ids=processed_ids,
    )

@router.get("/pull", response_model=SyncPullResponse)
async def pull_delta(
    since: Optional[datetime] = Query(None),
    x_tenant_id: str = Header(..., alias="X-Tenant-ID"),
    db: AsyncSession = Depends(get_db_session),
):
    try:
        tenant_uuid = uuid.UUID(x_tenant_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="X-Tenant-ID no válido")

    stmt = select(SolidarityPost).where(SolidarityPost.tenant_id == tenant_uuid)
    if since:
        stmt = stmt.where(SolidarityPost.updated_at > since)

    results = await db.execute(stmt)
    records = results.scalars().all()

    posts_list = []
    for r in records:
        posts_list.append({
            "id": str(r.id),
            "tenant_id": str(r.tenant_id),
            "author_user_id": str(r.author_user_id),
            "flow_type": r.flow_type,
            "modality": r.modality,
            "title": r.title,
            "description": r.description,
            "is_emergency_context": r.is_emergency_context,
            "status": r.status,
            "lat": r.lat,
            "lng": r.lng,
            "updated_at": r.updated_at.isoformat(),
            "is_deleted": r.is_deleted,
        })

    return SyncPullResponse(
        server_timestamp=datetime.now(timezone.utc),
        has_more=False,
        delta={"solidarity_posts": posts_list},
    )