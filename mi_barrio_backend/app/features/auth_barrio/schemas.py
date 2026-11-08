from datetime import datetime
import uuid
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, StringConstraints, model_validator
from typing import Annotated


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


Password = Annotated[str, StringConstraints(min_length=8, max_length=128)]


class RegisterRequest(BaseModel):
    full_name: str = Field(..., min_length=2, max_length=150)
    email: str = Field(..., min_length=5, max_length=254, pattern=r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
    password: Password
    role: Literal["VECINO", "COMERCIANTE"]
    join_code: str = Field(..., min_length=3, max_length=20)


class LoginRequest(BaseModel):
    email: str = Field(..., min_length=5, max_length=254, pattern=r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
    password: Password


class AuthUserResponse(BaseModel):
    id: uuid.UUID
    tenant_id: uuid.UUID | None
    full_name: str
    email: str
    role: Literal["VECINO", "COMERCIANTE", "ADMIN_BARRIO", "SUPER_ADMIN"]
    is_approved: bool = True
    tenant: TenantResponse | None


class AuthResponse(BaseModel):
    access_token: str
    token_type: Literal["bearer"] = "bearer"
    user: AuthUserResponse


class NeighborhoodAdminCreate(BaseModel):
    neighborhood_name: str | None = Field(default=None, min_length=2, max_length=100)
    join_code: str | None = Field(default=None, min_length=3, max_length=20)
    admin_full_name: str = Field(..., min_length=2, max_length=150)
    admin_email: str = Field(..., min_length=5, max_length=254, pattern=r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
    admin_password: Password
    center_lat: float | None = Field(default=None, ge=-90, le=90)
    center_lng: float | None = Field(default=None, ge=-180, le=180)

    @model_validator(mode="after")
    def require_coordinates_for_new_neighborhood(self):
        if self.join_code is None:
            if self.neighborhood_name is None:
                raise ValueError("Se requiere el nombre del barrio")
            if self.center_lat is None or self.center_lng is None:
                raise ValueError("Se requieren coordenadas para crear un barrio nuevo")
        return self


class NeighborhoodAdminCreated(BaseModel):
    neighborhood: TenantResponse
    administrator: AuthUserResponse


class TenantLookupResponse(BaseModel):
    """Lo mínimo para confirmar el barrio antes de registrarse (ruta pública)."""
    model_config = ConfigDict(from_attributes=True)

    name: str
    join_code: str
    center_lat: float
    center_lng: float


class UserProfileResponse(BaseModel):
    """Perfil completo del propio vecino (GET /users/me). Nunca se expone el de otros."""
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    tenant_id: uuid.UUID
    full_name: str
    email: str | None = None
    role: str
    is_approved: bool = True
    phone: str
    email_contacto: str | None = None
    address_reference: str | None = None
    home_lat: float
    home_lng: float
    tutorial_completed: bool
    whatsapp: str | None = None
    facebook_url: str | None = None
    instagram_url: str | None = None
    photo_b64: str | None = None
    publisher_type: str | None = None
    publisher_category: str | None = None
    publisher_name: str | None = None
    updated_at: datetime
