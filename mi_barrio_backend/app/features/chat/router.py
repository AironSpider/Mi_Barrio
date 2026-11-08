"""Chat en tiempo real entre vecinos sobre un favor o un servicio.

- Enviar: REST (queda guardado aunque el otro no esté conectado).
- Recibir al instante: WebSocket /api/v1/ws/chat.
- Conversación = (tipo, publicación, vecino). El dueño (autor del favor o
  comerciante) ve todas las de su publicación; cada vecino, solo la suya.
"""
import json
import uuid
from dataclasses import dataclass

from fastapi import APIRouter, Depends, HTTPException, Query, WebSocket, WebSocketDisconnect, status
from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.auth_security import decode_access_token
from app.core.database import get_db_session
from app.core.realtime import hub
from app.core.tenant_middleware import account_is_active, get_current_principal, get_current_tenant_id
from app.features.auth_barrio.service import public_profiles
from app.features.chat.models import ChatMessage
from app.features.chat.schemas import ChatKind, ConversationSummary, MessageCreate, MessageResponse
from app.features.proximity_services.models import LocalService
from app.features.solidarity_network.models import SolidarityPost

router = APIRouter(prefix="/api/v1/chat", tags=["Chat"])
realtime_router = APIRouter(prefix="/api/v1/ws", tags=["Tiempo real"])

_CONTEXT_TYPE = {"favor": "FAVOR", "service": "SERVICE"}
_KIND = {v: k for k, v in _CONTEXT_TYPE.items()}


@dataclass
class _Context:
    kind: str
    context_type: str
    id: uuid.UUID
    owner_user_id: uuid.UUID
    title: str


async def _context(db: AsyncSession, tenant_id: uuid.UUID, kind: str, context_id: uuid.UUID) -> _Context:
    """La publicación del chat (favor o servicio) y su dueño."""
    if kind == "favor":
        post = await db.scalar(select(SolidarityPost).where(
            SolidarityPost.id == context_id,
            SolidarityPost.tenant_id == tenant_id,
            SolidarityPost.is_deleted.is_(False),
        ))
        if post is None:
            raise HTTPException(status_code=404, detail="Publicación no encontrada en este barrio")
        return _Context(kind, "FAVOR", post.id, post.author_user_id, post.title)
    service = await db.scalar(select(LocalService).where(
        LocalService.id == context_id,
        LocalService.tenant_id == tenant_id,
        LocalService.is_deleted.is_(False),
    ))
    if service is None:
        raise HTTPException(status_code=404, detail="Servicio no encontrado en este barrio")
    title = f"{service.publisher_name}, {service.title}" if service.publisher_name else service.title
    return _Context(kind, "SERVICE", service.id, service.provider_user_id, title)


async def _names(db: AsyncSession, tenant_id: uuid.UUID, ids: set[uuid.UUID]) -> dict[uuid.UUID, str]:
    profiles = await public_profiles(db, tenant_id, ids)
    return {uid: p["name"] for uid, p in profiles.items()}


def _message_response(m: ChatMessage, names: dict[uuid.UUID, str]) -> MessageResponse:
    return MessageResponse(
        id=m.id, kind=_KIND[m.context_type], context_id=m.context_id,
        neighbor_user_id=m.neighbor_user_id, sender_user_id=m.sender_user_id,
        sender_name=names.get(m.sender_user_id, "Vecino"), body=m.body, created_at=m.created_at,
    )


def _check_participant(ctx: _Context, neighbor_id: uuid.UUID, me: uuid.UUID) -> None:
    if neighbor_id == ctx.owner_user_id:
        raise HTTPException(status_code=400, detail="La conversación es entre el dueño y otro vecino")
    if me not in (ctx.owner_user_id, neighbor_id):
        raise HTTPException(status_code=403, detail="No participas en esta conversación")


def _summaries(
    messages: list[ChatMessage],
    me: uuid.UUID,
    titles: dict[tuple[str, uuid.UUID], str],
    names: dict[uuid.UUID, str],
) -> list[ConversationSummary]:
    threads: dict[tuple[str, uuid.UUID, uuid.UUID], list[ChatMessage]] = {}
    for m in messages:
        threads.setdefault((m.context_type, m.context_id, m.neighbor_user_id), []).append(m)
    out = []
    for (ctype, cid, neighbor), msgs in threads.items():
        last = msgs[-1]
        other = neighbor if me == last.owner_user_id else last.owner_user_id
        out.append(ConversationSummary(
            kind=_KIND[ctype], context_id=cid, context_title=titles.get((ctype, cid), ""),
            owner_user_id=last.owner_user_id, neighbor_user_id=neighbor,
            other_user_id=other, other_name=names.get(other, "Vecino"),
            last_message=last.body, last_sender_user_id=last.sender_user_id,
            last_at=last.created_at, message_count=len(msgs),
        ))
    return sorted(out, key=lambda s: s.last_at, reverse=True)


@router.get("/inbox", response_model=list[ConversationSummary])
async def inbox(
    tenant_id: uuid.UUID = Depends(get_current_tenant_id),
    principal: dict = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db_session),
):
    """"Mis mensajes": todas mis conversaciones (como dueño o como vecino), la más reciente primero."""
    me = uuid.UUID(principal["sub"])
    messages = (await db.execute(
        select(ChatMessage).where(
            ChatMessage.tenant_id == tenant_id,
            ChatMessage.is_deleted.is_(False),
            or_(ChatMessage.owner_user_id == me, ChatMessage.neighbor_user_id == me),
        ).order_by(ChatMessage.created_at.asc()).limit(2000)
    )).scalars().all()

    favor_ids = {m.context_id for m in messages if m.context_type == "FAVOR"}
    service_ids = {m.context_id for m in messages if m.context_type == "SERVICE"}
    titles: dict[tuple[str, uuid.UUID], str] = {}
    if favor_ids:
        for pid, title in (await db.execute(
            select(SolidarityPost.id, SolidarityPost.title).where(SolidarityPost.id.in_(favor_ids))
        )).all():
            titles[("FAVOR", pid)] = title
    if service_ids:
        for sid, title, publisher in (await db.execute(
            select(LocalService.id, LocalService.title, LocalService.publisher_name)
            .where(LocalService.id.in_(service_ids))
        )).all():
            titles[("SERVICE", sid)] = f"{publisher}, {title}" if publisher else title
    people = {m.owner_user_id for m in messages} | {m.neighbor_user_id for m in messages}
    return _summaries(list(messages), me, titles, await _names(db, tenant_id, people))


@router.get("/{kind}/{context_id}/conversations", response_model=list[ConversationSummary])
async def list_conversations(
    kind: ChatKind,
    context_id: uuid.UUID,
    tenant_id: uuid.UUID = Depends(get_current_tenant_id),
    principal: dict = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db_session),
):
    """El dueño ve todas las conversaciones de su publicación; otro vecino, solo la suya."""
    ctx = await _context(db, tenant_id, kind, context_id)
    me = uuid.UUID(principal["sub"])
    stmt = select(ChatMessage).where(
        ChatMessage.context_type == ctx.context_type,
        ChatMessage.context_id == ctx.id,
        ChatMessage.tenant_id == tenant_id,
        ChatMessage.is_deleted.is_(False),
    )
    if me != ctx.owner_user_id:
        stmt = stmt.where(ChatMessage.neighbor_user_id == me)
    messages = (await db.execute(stmt.order_by(ChatMessage.created_at.asc()))).scalars().all()
    people = {ctx.owner_user_id} | {m.neighbor_user_id for m in messages}
    return _summaries(
        list(messages), me, {(ctx.context_type, ctx.id): ctx.title}, await _names(db, tenant_id, people)
    )


@router.get("/{kind}/{context_id}/conversations/{neighbor_id}/messages", response_model=list[MessageResponse])
async def list_messages(
    kind: ChatKind,
    context_id: uuid.UUID,
    neighbor_id: uuid.UUID,
    tenant_id: uuid.UUID = Depends(get_current_tenant_id),
    principal: dict = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db_session),
):
    ctx = await _context(db, tenant_id, kind, context_id)
    _check_participant(ctx, neighbor_id, uuid.UUID(principal["sub"]))
    messages = (await db.execute(
        select(ChatMessage).where(
            ChatMessage.context_type == ctx.context_type,
            ChatMessage.context_id == ctx.id,
            ChatMessage.neighbor_user_id == neighbor_id,
            ChatMessage.tenant_id == tenant_id,
            ChatMessage.is_deleted.is_(False),
        ).order_by(ChatMessage.created_at.asc()).limit(500)
    )).scalars().all()
    names = await _names(db, tenant_id, {ctx.owner_user_id, neighbor_id})
    return [_message_response(m, names) for m in messages]


@router.post(
    "/{kind}/{context_id}/conversations/{neighbor_id}/messages",
    response_model=MessageResponse,
    status_code=status.HTTP_201_CREATED,
)
async def send_message(
    kind: ChatKind,
    context_id: uuid.UUID,
    neighbor_id: uuid.UUID,
    payload: MessageCreate,
    tenant_id: uuid.UUID = Depends(get_current_tenant_id),
    principal: dict = Depends(get_current_principal),
    db: AsyncSession = Depends(get_db_session),
):
    """Guarda el mensaje y lo entrega AL INSTANTE (WebSocket) a los dos participantes."""
    ctx = await _context(db, tenant_id, kind, context_id)
    me = uuid.UUID(principal["sub"])
    _check_participant(ctx, neighbor_id, me)
    if me == ctx.owner_user_id:
        started = await db.scalar(select(ChatMessage.id).where(
            ChatMessage.context_type == ctx.context_type,
            ChatMessage.context_id == ctx.id,
            ChatMessage.neighbor_user_id == neighbor_id,
        ).limit(1))
        if started is None:
            raise HTTPException(status_code=409, detail="Ese vecino todavía no te escribió por esta publicación")

    message = ChatMessage(
        tenant_id=tenant_id, context_type=ctx.context_type, context_id=ctx.id,
        owner_user_id=ctx.owner_user_id, neighbor_user_id=neighbor_id,
        sender_user_id=me, body=payload.body.strip(),
    )
    db.add(message)
    await db.commit()
    await db.refresh(message)
    response = _message_response(message, await _names(db, tenant_id, {me}))
    await hub.send(
        {ctx.owner_user_id, neighbor_id},
        {
            "type": "chat_message",
            "context_title": ctx.title,
            "message": json.loads(response.model_dump_json()),
        },
    )
    return response


@realtime_router.websocket("/chat")
async def chat_socket(websocket: WebSocket, token: str = Query(...), tenant: str = Query(...)):
    """Canal en tiempo real: el teléfono se conecta con su token y recibe al
    instante los mensajes de sus conversaciones. Los WebSocket no pasan por el
    middleware HTTP: la sesión se valida aquí."""
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
