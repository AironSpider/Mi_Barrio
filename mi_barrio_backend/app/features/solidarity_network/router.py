import uuid
from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.core.database import get_db_session, get_current_tenant_id
from app.features.solidarity_network.models import SolidarityPost
from app.features.solidarity_network.schemas import (
    SolidarityPostCreate,
    SolidarityPostResponse,
)

router = APIRouter(prefix="/api/v1/solidarity", tags=["Solidarity Network"])

@router.post("", response_model=SolidarityPostResponse, status_code=status.HTTP_201_CREATED)
async def create_solidarity_post(
    payload: SolidarityPostCreate,
    tenant_id: uuid.UUID = Depends(get_current_tenant_id),
    db: AsyncSession = Depends(get_db_session),
):
    new_post = SolidarityPost(
        tenant_id=tenant_id,
        author_user_id=payload.author_user_id,
        flow_type=payload.flow_type,
        modality=payload.modality,
        title=payload.title,
        description=payload.description,
        is_emergency_context=payload.is_emergency_context,
        status=payload.status,
        lat=payload.lat,
        lng=payload.lng,
    )
    db.add(new_post)
    await db.commit()
    await db.refresh(new_post)
    return new_post

@router.get("", response_model=list[SolidarityPostResponse])
async def list_solidarity_posts(
    tenant_id: uuid.UUID = Depends(get_current_tenant_id),
    flow_type: str | None = Query(None, description="SOLICITO_AYUDA o OFREZCO_AYUDA"),
    emergency_only: bool = Query(False),
    db: AsyncSession = Depends(get_db_session),
):
    stmt = select(SolidarityPost).where(
        SolidarityPost.tenant_id == tenant_id,
        SolidarityPost.is_deleted.is_(False),
    )

    if flow_type:
        stmt = stmt.where(SolidarityPost.flow_type == flow_type)
    if emergency_only:
        stmt = stmt.where(SolidarityPost.is_emergency_context.is_(True))

    stmt = stmt.order_by(SolidarityPost.created_at.desc())
    result = await db.execute(stmt)
    return result.scalars().all()

@router.get("/{post_id}", response_model=SolidarityPostResponse)
async def get_solidarity_post(
    post_id: uuid.UUID,
    tenant_id: uuid.UUID = Depends(get_current_tenant_id),
    db: AsyncSession = Depends(get_db_session),
):
    stmt = select(SolidarityPost).where(
        SolidarityPost.id == post_id,
        SolidarityPost.tenant_id == tenant_id,
        SolidarityPost.is_deleted.is_(False),
    )
    result = await db.execute(stmt)
    post = result.scalar_one_or_none()

    if not post:
        raise HTTPException(status_code=404, detail="Publicación no encontrada en este barrio")
    return post

@router.delete("/{post_id}", status_code=status.HTTP_200_OK)
async def delete_solidarity_post(
    post_id: uuid.UUID,
    tenant_id: uuid.UUID = Depends(get_current_tenant_id),
    db: AsyncSession = Depends(get_db_session),
):
    stmt = select(SolidarityPost).where(
        SolidarityPost.id == post_id,
        SolidarityPost.tenant_id == tenant_id,
        SolidarityPost.is_deleted.is_(False),
    )
    result = await db.execute(stmt)
    post = result.scalar_one_or_none()

    if not post:
        raise HTTPException(status_code=404, detail="Publicación no encontrada en este barrio")

    post.is_deleted = True
    post.updated_at = datetime.now(timezone.utc)
    await db.commit()
    return {"success": True, "message": "Publicación marcada como eliminada"}