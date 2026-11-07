from pydantic import BaseModel, ConfigDict, Field
from typing import Optional
from datetime import datetime
import uuid

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
    pass

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
