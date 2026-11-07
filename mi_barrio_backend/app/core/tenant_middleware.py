import uuid
from fastapi import Header, Request, HTTPException, status
from fastapi.security import APIKeyHeader
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import JSONResponse

from app.core.auth_security import decode_access_token
from app.core.database import async_session_factory


async def _account_is_active(claims: dict) -> bool:
    """El token es válido solo si la cuenta sigue activa, en el mismo barrio y con el
    mismo rol. Así una cuenta borrada o degradada deja de operar al instante."""
    # Import local: los modelos importan core.database y evitamos ciclos.
    from app.features.auth_barrio.models import PlatformAdmin, User

    async with async_session_factory() as db:
        account_id = uuid.UUID(claims["sub"])
        if claims.get("role") == "SUPER_ADMIN":
            admin = await db.get(PlatformAdmin, account_id)
            return admin is not None and admin.is_active
        user = await db.get(User, account_id)
        return (
            user is not None
            and not user.is_deleted
            and str(user.tenant_id) == claims.get("tenant_id")
            and user.role == claims.get("role")
        )

tenant_header_scheme = APIKeyHeader(name="X-Tenant-ID", auto_error=False)

EXEMPT_PATHS = {
    "/health",
    "/docs",
    "/redoc",
    "/openapi.json",
}
PLATFORM_ADMIN_PREFIX = "/api/v1/platform/"

class TenantMiddleware(BaseHTTPMiddleware):
    """
    Middleware global que intercepta las peticiones a /api/v1/ y valida la presencia
    y formato del header X-Tenant-ID, inyectándolo en request.state.tenant_id.
    """
    async def dispatch(self, request: Request, call_next):
        if request.url.path in EXEMPT_PATHS or request.method == "OPTIONS":
            return await call_next(request)

        if request.url.path.startswith("/api/v1/"):
            is_public_auth = request.url.path in {
                "/api/v1/auth/login",
                "/api/v1/auth/register",
            }
            if not is_public_auth:
                authorization = request.headers.get("Authorization", "")
                scheme, _, token = authorization.partition(" ")
                if scheme.lower() != "bearer" or not token:
                    return JSONResponse(
                        status_code=status.HTTP_401_UNAUTHORIZED,
                        headers={"WWW-Authenticate": "Bearer"},
                        content={
                            "success": False,
                            "error": "Se requiere un token Bearer válido",
                            "data": None,
                        },
                    )
                try:
                    request.state.auth_claims = decode_access_token(token)
                    if not await _account_is_active(request.state.auth_claims):
                        return JSONResponse(
                            status_code=status.HTTP_401_UNAUTHORIZED,
                            headers={"WWW-Authenticate": "Bearer"},
                            content={
                                "success": False,
                                "error": "La sesión ya no es válida. Vuelve a iniciar sesión.",
                                "data": None,
                            },
                        )
                except HTTPException as exc:
                    return JSONResponse(
                        status_code=exc.status_code,
                        headers=exc.headers,
                        content={
                            "success": False,
                            "error": exc.detail,
                            "data": None,
                        },
                    )

            if request.url.path.startswith("/api/v1/auth/"):
                return await call_next(request)

            claims = getattr(request.state, "auth_claims", None)
            if request.url.path.startswith(PLATFORM_ADMIN_PREFIX):
                if claims is None or claims.get("role") != "SUPER_ADMIN":
                    return JSONResponse(
                        status_code=status.HTTP_403_FORBIDDEN,
                        content={
                            "success": False,
                            "error": "Solo el superadministrador puede gestionar barrios",
                            "data": None,
                        },
                    )
                return await call_next(request)

            tenant_id = request.headers.get("X-Tenant-ID")
            if not tenant_id:
                return JSONResponse(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    content={
                        "success": False,
                        "error": "Header 'X-Tenant-ID' es obligatorio para operaciones de barrio",
                        "data": None,
                    },
                )
            try:
                request.state.tenant_id = uuid.UUID(tenant_id)
            except ValueError:
                return JSONResponse(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    content={
                        "success": False,
                        "error": "Header 'X-Tenant-ID' debe ser un UUID válido",
                        "data": None,
                    },
                )
            if claims is not None and claims.get("role") == "SUPER_ADMIN":
                return JSONResponse(
                    status_code=status.HTTP_403_FORBIDDEN,
                    content={
                        "success": False,
                        "error": "El superadministrador no opera dentro de un barrio",
                        "data": None,
                    },
                )
            if claims is not None and claims["tenant_id"] != str(request.state.tenant_id):
                return JSONResponse(
                    status_code=status.HTTP_403_FORBIDDEN,
                    content={
                        "success": False,
                        "error": "El token no pertenece al barrio solicitado",
                        "data": None,
                    },
                )

        return await call_next(request)

def get_current_tenant_id(
    request: Request,
    # Declarado como Header para que Swagger (/docs) muestre el campo X-Tenant-ID.
    x_tenant_id: str = Header(..., alias="X-Tenant-ID", description="UUID del barrio"),
) -> uuid.UUID:
    """
    Dependencia FastAPI para inyectar directamente el UUID validado del tenant
    en cualquier endpoint.
    """
    tenant_id = getattr(request.state, "tenant_id", None)
    if not tenant_id:
        raw_header = request.headers.get("X-Tenant-ID")
        if not raw_header:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Header 'X-Tenant-ID' no presente en la petición",
            )
        try:
            tenant_id = uuid.UUID(raw_header)
        except ValueError:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Header 'X-Tenant-ID' inválido",
            )
    return tenant_id


def get_current_principal(request: Request) -> dict:
    claims = getattr(request.state, "auth_claims", None)
    if claims is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Se requiere una sesión Bearer",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return claims