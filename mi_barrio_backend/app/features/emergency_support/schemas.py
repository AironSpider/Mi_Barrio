from pydantic import BaseModel, ConfigDict, Field
from typing import Optional
from datetime import datetime
import uuid

from app.shared.contract_values import ReportStatus, UrgencyLevel, VulnerabilityType

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
    # Solo valores del contrato: Swagger los muestra como lista y rechaza "string".
    urgency_level: UrgencyLevel
    vulnerability_type: VulnerabilityType
    description: str = Field(..., min_length=1, examples=["Adulto mayor solo, necesita agua"])
    status: ReportStatus = "PENDIENTE_APOYO"
    lat: float = Field(..., ge=-90, le=90, examples=[-5.1945])
    lng: float = Field(..., ge=-180, le=180, examples=[-80.6328])

class VulnerableReportResponse(VulnerableReportBase):
    id: uuid.UUID
    tenant_id: uuid.UUID
    created_at: datetime
    updated_at: datetime
    is_deleted: bool

    model_config = ConfigDict(from_attributes=True)