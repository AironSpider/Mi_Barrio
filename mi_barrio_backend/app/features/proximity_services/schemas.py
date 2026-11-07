from pydantic import BaseModel, Field
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

class LocalServiceCreate(LocalServiceBase):
    pass

class LocalServiceResponse(LocalServiceBase):
    id: uuid.UUID
    tenant_id: uuid.UUID
    endorsements_count: int
    created_at: datetime
    updated_at: datetime
    is_deleted: bool

    class Config:
        from_attributes = True

class NeighborEndorsementCreate(BaseModel):
    service_id: uuid.UUID
    endorser_user_id: uuid.UUID
    short_comment: Optional[str] = Field(None, max_length=255)