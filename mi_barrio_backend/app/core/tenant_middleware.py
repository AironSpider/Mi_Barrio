import uuid
from fastapi import Request, HTTPException, Security, status
from fastapi.security import APIKeyHeader
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import JSONResponse

# Header extractor para documentación automática en Swagger
tenant_header_scheme = APIKeyHeader(name="X-Tenant-ID", auto_error=False)

# Rutas públicas que no requieren pertenecer a un barrio específico
EXEMPT_PATHS = {
    "/health",
    "/docs",
    "/redoc",
    "/openapi.json",
}

class TenantMiddleware(BaseHTTPMiddleware):
    """
    Middleware global que verifica la presencia y validez del header X-Tenant-ID.
    """
    async def dispatch(self, request: Request, call_next):
        # Excluir documentación y chequeo de salud
        if request.url.path in EXEMPT_PATHS or request.method == "OPTIONS":
            return await call_next(request)

        # Si la petición apunta a la API de negocio, validar el tenant
        if request.url.path.startswith("/api/v1/"):
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
                # Validar que sea un UUID v4 sintácticamente correcto
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

        return await call_next(request)


def get_current_tenant_id(request: Request) -> uuid.UUID:
    """
    Dependencia FastAPI para inyectar directamente el tenant_id (UUID)
    en cualquier endpoint o repositorio sin tener que parsearlo manualmente.
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