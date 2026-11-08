"""Esquemas (Pydantic) de cuentas, barrios y códigos de correo."""
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
    """Cuerpo para activar o desactivar el Modo Emergencia del barrio."""
    is_emergency_active: bool = Field(
        ..., description="true activa el Modo Emergencia para todo el barrio", examples=[True]
    )


Password = Annotated[str, StringConstraints(min_length=8, max_length=128)]


class RegisterRequest(BaseModel):
    """Datos para crear una cuenta con correo y contraseña."""
    full_name: str = Field(..., min_length=2, max_length=150)
    email: str = Field(..., min_length=5, max_length=254, pattern=r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
    password: Password
    role: Literal["VECINO", "COMERCIANTE"]
    join_code: str = Field(..., min_length=3, max_length=20)


class LoginRequest(BaseModel):
    """Correo y contraseña para iniciar sesión."""
    email: str = Field(..., min_length=5, max_length=254, pattern=r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
    password: Password


class AuthUserResponse(BaseModel):
    """La cuenta tal como la ve la app tras entrar (sin datos sensibles)."""
    id: uuid.UUID
    tenant_id: uuid.UUID | None
    full_name: str
    email: str
    role: Literal["VECINO", "COMERCIANTE", "ADMIN_BARRIO", "SUPER_ADMIN"]
    is_approved: bool = True
    email_verified: bool = True
    # False = entró con Google y todavía no creó una contraseña.
    has_password: bool = True
    tenant: TenantResponse | None


class AuthResponse(BaseModel):
    """Respuesta al entrar: token de sesión + la cuenta."""
    access_token: str
    token_type: Literal["bearer"] = "bearer"
    user: AuthUserResponse


Email = Annotated[
    str,
    StringConstraints(
        strip_whitespace=True, min_length=5, max_length=254, pattern=r"^[^@\s]+@[^@\s]+\.[^@\s]+$"
    ),
]
Code = Annotated[str, StringConstraints(strip_whitespace=True, pattern=r"^\d{6}$")]


class EmailRequest(BaseModel):
    """Solo un correo (para pedir códigos)."""
    email: Email


class VerifyEmailRequest(BaseModel):
    """Correo + código de 6 números para confirmarlo."""
    email: Email
    code: Code


class ResetPasswordRequest(BaseModel):
    """Correo + código + contraseña nueva."""
    email: Email
    code: Code
    new_password: Password


class GoogleLoginRequest(BaseModel):
    """ID token de Google y, solo la primera vez, el código del barrio y el rol."""
    id_token: str = Field(..., min_length=20, max_length=4096)
    # Solo para crear la cuenta la primera vez: a qué barrio entra y con qué rol.
    join_code: str | None = Field(default=None, min_length=3, max_length=20)
    role: Literal["VECINO", "COMERCIANTE"] = "VECINO"


class SetPasswordRequest(BaseModel):
    """Contraseña nueva para quien entró con Google y aún no tiene una."""
    password: Password


class CodeSentResponse(BaseModel):
    """Respuesta al pedir un código: siempre el mismo mensaje, exista o no la cuenta."""
    sent: bool = True
    message: str
    # Solo con AUTH_DEBUG_CODES=1 y sin correo configurado (pruebas locales).
    debug_code: str | None = None


class NeighborhoodAdminCreate(BaseModel):
    """Datos del superadministrador para crear un barrio y su administrador."""
    neighborhood_name: str | None = Field(default=None, min_length=2, max_length=100)
    join_code: str | None = Field(default=None, min_length=3, max_length=20)
    admin_full_name: str = Field(..., min_length=2, max_length=150)
    admin_email: str = Field(..., min_length=5, max_length=254, pattern=r"^[^@\s]+@[^@\s]+\.[^@\s]+$")
    admin_password: Password
    center_lat: float | None = Field(default=None, ge=-90, le=90)
    center_lng: float | None = Field(default=None, ge=-180, le=180)

    @model_validator(mode="after")
    def require_coordinates_for_new_neighborhood(self):
        """Un barrio nuevo necesita nombre y coordenadas; uno existente se indica por su código."""
        if self.join_code is None:
            if self.neighborhood_name is None:
                raise ValueError("Se requiere el nombre del barrio")
            if self.center_lat is None or self.center_lng is None:
                raise ValueError("Se requieren coordenadas para crear un barrio nuevo")
        return self


class NeighborhoodAdminCreated(BaseModel):
    """Barrio y administrador recién creados."""
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
