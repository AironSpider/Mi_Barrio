import json
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException, Query, WebSocket, WebSocketDisconnect, status
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.auth_security import decode_access_token
from app.core.database import get_db_session
from app.core.realtime import hub
from app.core.tenant_middleware import account_is_active, get_current_principal, get_current_tenant_id
from app.features.auth_barrio.service import public_profiles
from app.features.solidarity_network.models import FavorMessage, FavorReview, PostComment, SolidarityPost
from app.features.solidarity_network.schemas import (
    CommentCreate,
    CommentResponse,
    ConversationSummary,
    MessageCreate,
    MessageResponse,
    PostPhotoResponse,
    ReviewCreate,
    ReviewResponse,
    SolidarityPostCreate,
    SolidarityPostResponse,
)

router = APIRouter(prefix="/api/v1/solidarity", tags=["Solidarity Network"])
realtime_router = APIRouter(prefix="/api/v1/ws", tags=["Tiempo real"])


async def _post_or_404(
    db: AsyncSession, tenant_id: uuid.UUID, post_id: uuid.UUID, *, for_update: bool = False
) -> SolidarityPost:
    stmt = select(SolidarityPost).where(
        SolidarityPost.id == post_id,
        SolidarityPost.tenant_id == tenant_id,
        SolidarityPost.is_deleted.is_(False),
    )
    if for_update:
        stmt = stmt.with_for_update()
    post = (await db.execute(stmt)).scalar_one_or_none()
    if post is None:
        raise HTTPException(status_code=404, detail="Publicación no encontrada en este barrio")
    return post


async def _names(db: AsyncSession, tenant_id: uuid.UUID, ids: set[uuid.UUID]) -> dict[uuid.UUID, str]:
    profiles = await public_profiles(db, tenant_id, ids)
    return {uid: p["name"] for uid, p in profiles.items()}


@router.post("", response_model=SolidarityPostResponse, status_code=status.HTTP_201_CREATED)
async def create_solidarity_post(
    payload: SolidarityPostCreate,
    tenant_id: uuid.UUID = Depends(get_current_tenant_id),
    principal: dict = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db_session),
):
    author_id = uuid.UUID(principal["sub"])
    if payload.author_user_id != author_id:
        raise HTTPException(status_code=403, detail="No puedes publicar a nombre de otro usuario")
    new_post = SolidarityPost(
        tenant_id=tenant_id,
        author_user_id=author_id,
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
    return await _post_or_404(db, tenant_id, post_id)


@router.get("/{post_id}/photo", response_model=PostPhotoResponse)
async def get_solidarity_post_photo(
    post_id: uuid.UUID,
    tenant_id: uuid.UUID = Depends(get_current_tenant_id),
    db: AsyncSession = Depends(get_db_session),
):
    """La foto va aparte para que el muro y el pull pesen poco."""
    post = await _post_or_404(db, tenant_id, post_id)
    if not post.photo_b64:
        raise HTTPException(status_code=404, detail="Esta publicación no tiene foto")
    return PostPhotoResponse(id=post.id, photo_b64=post.photo_b64)


@router.patch("/{post_id}/coordinate", response_model=SolidarityPostResponse)
async def coordinate_solidarity_post(
    post_id: uuid.UUID,
    tenant_id: uuid.UUID = Depends(get_current_tenant_id),
    principal: dict = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db_session),
):
    post = await _post_or_404(db, tenant_id, post_id, for_update=True)
    me = uuid.UUID(principal["sub"])
    if post.author_user_id == me:
        raise HTTPException(status_code=403, detail="Solo otra persona puede coordinar esta publicación")
    if post.status not in ("DISPONIBLE", "EN_COORDINACION"):
        raise HTTPException(status_code=409, detail="Esta publicación ya no está disponible para coordinar")

    post.status = "EN_COORDINACION"
    post.coordinator_user_id = me
    post.updated_at = datetime.now(timezone.utc)
    await db.commit()
    await db.refresh(post)
    return post


@router.delete("/{post_id}", status_code=status.HTTP_200_OK)
async def delete_solidarity_post(
    post_id: uuid.UUID,
    tenant_id: uuid.UUID = Depends(get_current_tenant_id),
    principal: dict = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db_session),
):
    post = await _post_or_404(db, tenant_id, post_id)
    if post.author_user_id != uuid.UUID(principal["sub"]):
        raise HTTPException(status_code=403, detail="Solo quien publicó puede eliminarla")

    post.is_deleted = True
    post.updated_at = datetime.now(timezone.utc)
    await db.commit()
    return {"success": True, "message": "Publicación marcada como eliminada"}


# ── Comentarios públicos ──

@router.get("/{post_id}/comments", response_model=list[CommentResponse])
async def list_comments(
    post_id: uuid.UUID,
    tenant_id: uuid.UUID = Depends(get_current_tenant_id),
    db: AsyncSession = Depends(get_db_session),
):
    await _post_or_404(db, tenant_id, post_id)
    comments = (await db.execute(
        select(PostComment).where(
            PostComment.post_id == post_id,
            PostComment.tenant_id == tenant_id,
            PostComment.is_deleted.is_(False),
        ).order_by(PostComment.created_at.asc())
    )).scalars().all()
    names = await _names(db, tenant_id, {c.author_user_id for c in comments})
    return [
        CommentResponse(
            id=c.id, post_id=c.post_id, author_user_id=c.author_user_id,
            author_name=names.get(c.author_user_id, "Vecino"), body=c.body, created_at=c.created_at,
        )
        for c in comments
    ]


@router.post("/{post_id}/comments", response_model=CommentResponse, status_code=status.HTTP_201_CREATED)
async def create_comment(
    post_id: uuid.UUID,
    payload: CommentCreate,
    tenant_id: uuid.UUID = Depends(get_current_tenant_id),
    principal: dict = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db_session),
):
    await _post_or_404(db, tenant_id, post_id)
    me = uuid.UUID(principal["sub"])
    comment = PostComment(tenant_id=tenant_id, post_id=post_id, author_user_id=me, body=payload.body.strip())
    db.add(comment)
    await db.commit()
    await db.refresh(comment)
    names = await _names(db, tenant_id, {me})
    return CommentResponse(
        id=comment.id, post_id=post_id, author_user_id=me,
        author_name=names.get(me, "Vecino"), body=comment.body, created_at=comment.created_at,
    )


@router.delete("/{post_id}/comments/{comment_id}", status_code=status.HTTP_200_OK)
async def delete_comment(
    post_id: uuid.UUID,
    comment_id: uuid.UUID,
    tenant_id: uuid.UUID = Depends(get_current_tenant_id),
    principal: dict = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db_session),
):
    comment = await db.scalar(select(PostComment).where(
        PostComment.id == comment_id,
        PostComment.post_id == post_id,
        PostComment.tenant_id == tenant_id,
        PostComment.is_deleted.is_(False),
    ))
    if comment is None:
        raise HTTPException(status_code=404, detail="Comentario no encontrado")
    if comment.author_user_id != uuid.UUID(principal["sub"]):
        raise HTTPException(status_code=403, detail="Solo quien comentó puede borrarlo")
    comment.is_deleted = True
    await db.commit()
    return {"success": True}


# ── Reseñas al completar ──

@router.get("/{post_id}/reviews", response_model=list[ReviewResponse])
async def list_reviews(
    post_id: uuid.UUID,
    tenant_id: uuid.UUID = Depends(get_current_tenant_id),
    db: AsyncSession = Depends(get_db_session),
):
    await _post_or_404(db, tenant_id, post_id)
    reviews = (await db.execute(
        select(FavorReview).where(
            FavorReview.post_id == post_id,
            FavorReview.tenant_id == tenant_id,
            FavorReview.is_deleted.is_(False),
        ).order_by(FavorReview.created_at.asc())
    )).scalars().all()
    names = await _names(db, tenant_id, {r.reviewer_user_id for r in reviews} | {r.reviewed_user_id for r in reviews})
    return [_review_response(r, names) for r in reviews]


def _review_response(r: FavorReview, names: dict[uuid.UUID, str]) -> ReviewResponse:
    return ReviewResponse(
        id=r.id, post_id=r.post_id,
        reviewer_user_id=r.reviewer_user_id, reviewer_name=names.get(r.reviewer_user_id, "Vecino"),
        reviewed_user_id=r.reviewed_user_id, reviewed_name=names.get(r.reviewed_user_id, "Vecino"),
        rating=r.rating, comment=r.comment, created_at=r.created_at,
    )


@router.post("/{post_id}/reviews", response_model=ReviewResponse, status_code=status.HTTP_201_CREATED)
async def create_review(
    post_id: uuid.UUID,
    payload: ReviewCreate,
    tenant_id: uuid.UUID = Depends(get_current_tenant_id),
    principal: dict = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db_session),
):
    """Solo cuando el favor está COMPLETADO: el autor califica a quien ayudó y
    quien ayudó califica al autor. Una reseña por persona y favor."""
    post = await _post_or_404(db, tenant_id, post_id)
    me = uuid.UUID(principal["sub"])
    if post.status != "COMPLETADO":
        raise HTTPException(status_code=409, detail="Podrás dejar tu reseña cuando el favor esté completado")
    if post.coordinator_user_id is None:
        raise HTTPException(status_code=409, detail="Este favor no tiene registrado quién ayudó")
    if me == post.author_user_id:
        reviewed = post.coordinator_user_id
    elif me == post.coordinator_user_id:
        reviewed = post.author_user_id
    else:
        raise HTTPException(status_code=403, detail="Solo quienes participaron en el favor pueden dejar reseña")

    review = FavorReview(
        tenant_id=tenant_id, post_id=post_id, reviewer_user_id=me, reviewed_user_id=reviewed,
        rating=payload.rating, comment=(payload.comment or "").strip() or None,
    )
    db.add(review)
    try:
        await db.commit()
    except IntegrityError as exc:
        await db.rollback()
        raise HTTPException(status_code=409, detail="Ya dejaste tu reseña para este favor") from exc
    await db.refresh(review)
    return _review_response(review, await _names(db, tenant_id, {me, reviewed}))


# ── Chat del favor (autor ↔ cada vecino interesado) ──

def _message_response(m: FavorMessage, names: dict[uuid.UUID, str]) -> MessageResponse:
    return MessageResponse(
        id=m.id, post_id=m.post_id, neighbor_user_id=m.neighbor_user_id,
        sender_user_id=m.sender_user_id, sender_name=names.get(m.sender_user_id, "Vecino"),
        body=m.body, created_at=m.created_at,
    )


def _check_participant(post: SolidarityPost, neighbor_id: uuid.UUID, me: uuid.UUID) -> None:
    if neighbor_id == post.author_user_id:
        raise HTTPException(status_code=400, detail="La conversación es entre el autor y otro vecino")
    if me not in (post.author_user_id, neighbor_id):
        raise HTTPException(status_code=403, detail="No participas en esta conversación")


@router.get("/{post_id}/conversations", response_model=list[ConversationSummary])
async def list_conversations(
    post_id: uuid.UUID,
    tenant_id: uuid.UUID = Depends(get_current_tenant_id),
    principal: dict = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db_session),
):
    """El autor ve todas las conversaciones de su favor; otro vecino, solo la suya."""
    post = await _post_or_404(db, tenant_id, post_id)
    me = uuid.UUID(principal["sub"])
    stmt = select(FavorMessage).where(
        FavorMessage.post_id == post_id,
        FavorMessage.tenant_id == tenant_id,
        FavorMessage.is_deleted.is_(False),
    )
    if me != post.author_user_id:
        stmt = stmt.where(FavorMessage.neighbor_user_id == me)
    messages = (await db.execute(stmt.order_by(FavorMessage.created_at.asc()))).scalars().all()
    threads: dict[uuid.UUID, list[FavorMessage]] = {}
    for m in messages:
        threads.setdefault(m.neighbor_user_id, []).append(m)
    names = await _names(db, tenant_id, set(threads))
    summaries = [
        ConversationSummary(
            post_id=post_id, neighbor_user_id=nid, neighbor_name=names.get(nid, "Vecino"),
            last_message=msgs[-1].body, last_sender_user_id=msgs[-1].sender_user_id,
            last_at=msgs[-1].created_at, message_count=len(msgs),
        )
        for nid, msgs in threads.items()
    ]
    return sorted(summaries, key=lambda s: s.last_at, reverse=True)


@router.get("/{post_id}/conversations/{neighbor_id}/messages", response_model=list[MessageResponse])
async def list_messages(
    post_id: uuid.UUID,
    neighbor_id: uuid.UUID,
    tenant_id: uuid.UUID = Depends(get_current_tenant_id),
    principal: dict = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db_session),
):
    post = await _post_or_404(db, tenant_id, post_id)
    _check_participant(post, neighbor_id, uuid.UUID(principal["sub"]))
    messages = (await db.execute(
        select(FavorMessage).where(
            FavorMessage.post_id == post_id,
            FavorMessage.neighbor_user_id == neighbor_id,
            FavorMessage.tenant_id == tenant_id,
            FavorMessage.is_deleted.is_(False),
        ).order_by(FavorMessage.created_at.asc()).limit(500)
    )).scalars().all()
    names = await _names(db, tenant_id, {post.author_user_id, neighbor_id})
    return [_message_response(m, names) for m in messages]


@router.post(
    "/{post_id}/conversations/{neighbor_id}/messages",
    response_model=MessageResponse,
    status_code=status.HTTP_201_CREATED,
)
async def send_message(
    post_id: uuid.UUID,
    neighbor_id: uuid.UUID,
    payload: MessageCreate,
    tenant_id: uuid.UUID = Depends(get_current_tenant_id),
    principal: dict = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db_session),
):
    """Guarda el mensaje y lo entrega AL INSTANTE (WebSocket) a los dos participantes."""
    post = await _post_or_404(db, tenant_id, post_id)
    me = uuid.UUID(principal["sub"])
    _check_participant(post, neighbor_id, me)
    if me == post.author_user_id:
        started = await db.scalar(select(func.count()).select_from(FavorMessage).where(
            FavorMessage.post_id == post_id, FavorMessage.neighbor_user_id == neighbor_id,
        ))
        if not started:
            raise HTTPException(status_code=409, detail="Ese vecino todavía no te escribió por este favor")

    message = FavorMessage(
        tenant_id=tenant_id, post_id=post_id, neighbor_user_id=neighbor_id,
        sender_user_id=me, body=payload.body.strip(),
    )
    db.add(message)
    await db.commit()
    await db.refresh(message)
    response = _message_response(message, await _names(db, tenant_id, {me}))
    await hub.send(
        {post.author_user_id, neighbor_id},
        {"type": "favor_message", "post_title": post.title, "message": json.loads(response.model_dump_json())},
    )
    return response


@realtime_router.websocket("/chat")
async def chat_socket(websocket: WebSocket, token: str = Query(...), tenant: str = Query(...)):
    """Canal en tiempo real. El teléfono se conecta con su token y recibe al
    instante los mensajes de sus conversaciones. Enviar se hace por REST
    (queda guardado aunque el otro no esté conectado).

    Los WebSocket no pasan por el middleware HTTP: la sesión se valida aquí."""
    try:
        claims = decode_access_token(token)
        if claims.get("tenant_id") != str(uuid.UUID(tenant)) or not await account_is_active(claims):
            raise ValueError("sesión inválida")
    except Exception:  # noqa: BLE001 - cualquier fallo = no autorizado
        await websocket.close(code=4401)
        return

    user_id = uuid.UUID(claims["sub"])
    await websocket.accept()
    await hub.connect(user_id, websocket)
    try:
        while True:
            # El teléfono manda "ping" cada ~25 s para mantener viva la conexión.
            if await websocket.receive_text() == "ping":
                await websocket.send_text("pong")
    except WebSocketDisconnect:
        pass
    finally:
        await hub.disconnect(user_id, websocket)

