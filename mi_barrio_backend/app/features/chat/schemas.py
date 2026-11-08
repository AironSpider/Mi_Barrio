import uuid
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field

# En la URL: /chat/favor/{id} o /chat/service/{id}
ChatKind = Literal["favor", "service"]


class MessageCreate(BaseModel):
    body: str = Field(..., min_length=1, max_length=1000)


class MessageResponse(BaseModel):
    id: uuid.UUID
    kind: ChatKind
    context_id: uuid.UUID
    neighbor_user_id: uuid.UUID
    sender_user_id: uuid.UUID
    sender_name: str
    body: str
    created_at: datetime


class ConversationSummary(BaseModel):
    """Una conversación (dueño ↔ un vecino) de una publicación."""
    kind: ChatKind
    context_id: uuid.UUID
    context_title: str
    owner_user_id: uuid.UUID
    neighbor_user_id: uuid.UUID
    # La otra persona, vista por quien consulta.
    other_user_id: uuid.UUID
    other_name: str
    last_message: str
    last_sender_user_id: uuid.UUID
    last_at: datetime
    message_count: int
