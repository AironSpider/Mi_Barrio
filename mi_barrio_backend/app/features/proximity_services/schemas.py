from pydantic import BaseModel, ConfigDict, Field, StringConstraints
from typing import Annotated, Optional
from datetime import datetime
import uuid

from app.shared.contract_values import MAX_PHOTO_B64, MAX_SERVICE_PHOTOS, FlowType, PublisherType, ServiceCategory

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
    price_text: Optional[str] = Field(None, max_length=60, examples=["S/ 30 la visita"])
    # Ofrezco o Necesito (mismos valores que el muro).
    flow_type: str = "OFREZCO_AYUDA"

class LocalServiceCreate(LocalServiceBase):
    # Solo valores del contrato: Swagger los muestra como lista y rechaza "string".
    category: ServiceCategory
    title: str = Field(..., min_length=1, max_length=200, examples=["Don Pedro, gasfitero"])
    publisher_type: Optional[PublisherType] = None
    flow_type: FlowType = "OFREZCO_AYUDA"
    lat: float = Field(..., ge=-90, le=90, examples=[-5.1945])
    lng: float = Field(..., ge=-180, le=180, examples=[-80.6328])
    photos: Optional[list[Annotated[str, StringConstraints(min_length=1, max_length=MAX_PHOTO_B64)]]] = Field(
        None, max_length=MAX_SERVICE_PHOTOS
    )

class LocalServiceResponse(LocalServiceBase):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    tenant_id: uuid.UUID
    endorsements_count: int
    # Promedio de estrellas calculado por el servidor (null = sin calificaciones).
    rating_avg: Optional[float] = None
    # Cuántas fotos tiene (se piden aparte en /services/{id}/photos).
    photo_count: int = 0
    created_at: datetime
    updated_at: datetime
    is_deleted: bool
    is_under_review: bool = False

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
    # Nombre público de quien califica ("Rosa C.").
    endorser_name: str = "Vecino"
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


class ServicePhotosResponse(BaseModel):
    id: uuid.UUID
    photos: list[str]
    content_type: str = "image/jpeg"
