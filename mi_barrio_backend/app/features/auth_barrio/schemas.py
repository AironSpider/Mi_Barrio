import uuid

from pydantic import BaseModel, ConfigDict, Field


class TenantResponse(BaseModel):
    """Datos públicos del barrio (junta vecinal)."""
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    name: str
    join_code: str
    center_lat: float
    center_lng: float
    is_emergency_active: bool


class EmergencyToggleRequest(BaseModel):
    is_emergency_active: bool = Field(
        ..., description="true activa el Modo Emergencia para todo el barrio", examples=[True]
    )
