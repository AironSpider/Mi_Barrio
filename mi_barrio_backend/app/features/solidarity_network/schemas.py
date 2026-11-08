from pydantic import BaseModel, ConfigDict, Field
from typing import Optional
from datetime import datetime
import uuid

from app.shared.contract_values import FlowType, Modality, PostStatus

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
# Solo valores del contrato: Swagger los muestra como lista y rechaza "string".
class SolidarityPostCreate(SolidarityPostBase):
    flow_type: FlowType
    modality: Modality
    title: str = Field(..., min_length=1, max_length=200, examples=["Préstamo de escalera"])
    status: PostStatus = "DISPONIBLE"
    lat: float = Field(..., ge=-90, le=90, examples=[-5.1945])
    lng: float = Field(..., ge=-180, le=180, examples=[-80.6328])

# 3. Schema de Respuesta (GET / POST devuelto)
class SolidarityPostResponse(SolidarityPostBase):
    # Configuración vital para que Pydantic lea los objetos de SQLAlchemy
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    tenant_id: uuid.UUID
    created_at: datetime
    updated_at: datetime
    is_deleted: bool
    coordinator_user_id: Optional[uuid.UUID] = None


class PostPhotoResponse(BaseModel):
    id: uuid.UUID
    photo_b64: str
    content_type: str = "image/jpeg"


# ── Comentarios ──
class CommentCreate(BaseModel):
    body: str = Field(..., min_length=1, max_length=500, examples=["¡Yo te presto la escalera!"])


class CommentResponse(BaseModel):
    id: uuid.UUID
    post_id: uuid.UUID
    author_user_id: uuid.UUID
    author_name: str
    body: str
    created_at: datetime


# ── Reseñas (al completar el favor) ──
class ReviewCreate(BaseModel):
    rating: int = Field(..., ge=1, le=5)
    comment: Optional[str] = Field(None, max_length=300)


class ReviewResponse(BaseModel):
    id: uuid.UUID
    post_id: uuid.UUID
    reviewer_user_id: uuid.UUID
    reviewer_name: str
    reviewed_user_id: uuid.UUID
    reviewed_name: str
    rating: int
    comment: Optional[str] = None
    created_at: datetime
