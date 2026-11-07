from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime
import uuid

# 1. Base compartida (datos que siempre viajan)
class SolidarityPostBase(BaseModel):
    author_user_id: uuid.UUID
    flow_type: str = Field(..., description="Debe ser 'SOLICITO_AYUDA' o 'OFREZCO_AYUDA'")
    modality: str = Field(..., description="Ej: 'PRESTAMO_HERRAMIENTA', 'RECURSO_CRITICO'")
    title: str = Field(..., max_length=200)
    description: Optional[str] = None
    is_emergency_context: bool = False
    status: str = "DISPONIBLE"
    lat: float
    lng: float

# 2. Schema para Crear (POST)
# Nota: No pedimos el tenant_id aquí porque se inyecta seguro desde el header X-Tenant-ID
class SolidarityPostCreate(SolidarityPostBase):
    pass

# 3. Schema de Respuesta (GET / POST devuelto)
class SolidarityPostResponse(SolidarityPostBase):
    id: uuid.UUID
    tenant_id: uuid.UUID
    created_at: datetime
    updated_at: datetime
    is_deleted: bool

    class Config:
        # Configuración vital para que Pydantic lea los objetos de SQLAlchemy
        from_attributes = True