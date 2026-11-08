from pydantic import BaseModel, ConfigDict, Field
from typing import Optional
from datetime import datetime
import uuid

from app.shared.contract_values import PublisherType, ServiceCategory

class LocalServiceBase(BaseModel):
    provider_user_id: uuid.UUID
    category: str = Field(..., max_length=50)
    title: str = Field(..., max_length=200)
    description: str
    is_available_in_emergency: bool = False
    lat: float
    lng: float
    publisher_type: Optional[str] = Field(None, max_length=30)
    publisher_name: Optional[str] = Field(None, max_length=120)

class LocalServiceCreate(LocalServiceBase):
    # Solo valores del contrato: Swagger los muestra como lista y rechaza "string".
    category: ServiceCategory
    title: str = Field(..., min_length=1, max_length=200, examples=["Don Pedro, gasfitero"])
    publisher_type: Optional[PublisherType] = None
    lat: float = Field(..., ge=-90, le=90, examples=[-5.1945])
    lng: float = Field(..., ge=-180, le=180, examples=[-80.6328])

class LocalServiceResponse(LocalServiceBase):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    tenant_id: uuid.UUID
    endorsements_count: int
    # Promedio de estrellas calculado por el servidor (null = sin calificaciones).
    rating_avg: Optional[float] = None
    created_at: datetime
    updated_at: datetime
    is_deleted: bool

class NeighborEndorsementCreate(BaseModel):
    service_id: uuid.UUID
    endorser_user_id: uuid.UUID
    # Estrellas 1 a 5; null = deja las estrellas vacías.
    rating: Optional[int] = Field(None, ge=1, le=5)
    short_comment: Optional[str] = Field(None, max_length=255)
    # JPEG comprimido en base64 (~480 px): tope ~110 KB.
    photo_b64: Optional[str] = Field(None, max_length=110_000)


class NeighborEndorsementResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    service_id: uuid.UUID
    endorser_user_id: uuid.UUID
    rating: Optional[int]
    short_comment: Optional[str]
    provider_reply: Optional[str] = None
    replied_at: Optional[datetime] = None
    # true si tiene foto (se pide aparte en /endorsements/{id}/photo).
    has_photo: bool = False
    created_at: datetime
    updated_at: datetime


class EndorsementPhotoResponse(BaseModel):
    id: uuid.UUID
    photo_b64: str
    content_type: str = "image/jpeg"


class EndorsementReplyRequest(BaseModel):
    reply: str = Field(..., min_length=1, max_length=1000)
