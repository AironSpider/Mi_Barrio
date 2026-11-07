import uuid
from fastapi import Request, HTTPException, status
from fastapi.security import APIKeyHeader
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import JSONResponse

# Header scheme para que Swagger UI lo detecte automáticamente
tenant_header_scheme = APIKeyHeader(name="X-Tenant-ID", auto_error=False)

# Endpoints que no requieren pertenecer a un barrio (ej. documentación o estado de salud)
EXEMPT_PATHS = {
    "/health",
    "/docs",
    "/redoc",
    "/openapi.json",
}

class TenantMiddleware(BaseHTTPMiddleware):
    """
    Middleware global que verifica la presencia y validez del header X-Tenant-ID
    en todas las peticiones a la API de negocio.
    """
    async def dispatch(self, request: Request, call_next):
        # Permitir paso a rutas exentas y peticiones CORS (OPTIONS)
        if request.url.path in EXEMPT_PATHS or request.method == "OPTIONS":
            return await call_next(request)

        # Aplicar validación estricta solo a los endpoints de la API (v1)
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
                # Validar formato UUID y almacenarlo en el contexto de la petición
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
    Dependencia de FastAPI (Depends) para inyectar el UUID del tenant en los endpoints
    de forma limpia, leyéndolo desde el estado pre-validado por el middleware.
    """
    tenant_id = getattr(request.state, "tenant_id", None)
    if not tenant_id:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Error de configuración: X-Tenant-ID no encontrado en el contexto de la petición.",
        )
    return tenant_id