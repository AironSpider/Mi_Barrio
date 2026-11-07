from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime
import uuid

class VulnerableReportBase(BaseModel):
    reporter_user_id: uuid.UUID
    urgency_level: str = Field(..., description="CRITICA, ALTA, MEDIA")
    vulnerability_type: str = Field(..., max_length=50)
    description: str
    lat: float
    lng: float
    status: str = "PENDIENTE_APOYO"
    helper_user_id: Optional[uuid.UUID] = None

class VulnerableReportCreate(VulnerableReportBase):
    pass

class VulnerableReportResponse(VulnerableReportBase):
    id: uuid.UUID
    tenant_id: uuid.UUID
    created_at: datetime
    updated_at: datetime
    is_deleted: bool

    class Config:
        from_attributes = True