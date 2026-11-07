import uuid
from fastapi import Header, Request, HTTPException, status
from fastapi.security import APIKeyHeader
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import JSONResponse

tenant_header_scheme = APIKeyHeader(name="X-Tenant-ID", auto_error=False)

EXEMPT_PATHS = {
    "/health",
    "/docs",
    "/redoc",
    "/openapi.json",
}

class TenantMiddleware(BaseHTTPMiddleware):
    """
    Middleware global que intercepta las peticiones a /api/v1/ y valida la presencia
    y formato del header X-Tenant-ID, inyectándolo en request.state.tenant_id.
    """
    async def dispatch(self, request: Request, call_next):
        if request.url.path in EXEMPT_PATHS or request.method == "OPTIONS":
            return await call_next(request)

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