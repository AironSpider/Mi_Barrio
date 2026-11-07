import logging

from fastapi import Request
from fastapi.responses import JSONResponse
from fastapi.exceptions import RequestValidationError
from starlette.exceptions import HTTPException as StarletteHTTPException

logger = logging.getLogger("mi_barrio.errors")

async def custom_http_exception_handler(request: Request, exc: StarletteHTTPException):
    return JSONResponse(
        status_code=exc.status_code,
        content={"success": False, "error": exc.detail, "data": None},
    )

async def validation_exception_handler(request: Request, exc: RequestValidationError):
    return JSONResponse(
        status_code=422,
        content={
            "success": False,
            "error": "Error de validación en los datos enviados",
            "details": exc.errors()
        },
    )


def _hint(message: str) -> str | None:
    """Pista para los errores más comunes al levantar el backend en otra PC."""
    m = message.lower()
    if "does not exist" in m and ("column" in m or "relation" in m or "columna" in m or "relación" in m):
        return "Faltan migraciones en tu base de datos: ejecuta `alembic upgrade head`."
    if "password authentication failed" in m or "autenticação" in m or "autenticación" in m:
        return "Contraseña de PostgreSQL incorrecta: revisa la variable DATABASE_URL."
    if "connect call failed" in m or "connection refused" in m or "could not connect" in m:
        return "PostgreSQL no está encendido o DATABASE_URL apunta a otro host/puerto."
    if "does not exist" in m and "database" in m:
        return "La base de datos no existe: créala (mi_barrio_db) en pgAdmin."
    return None


async def unhandled_exception_handler(request: Request, exc: Exception):
    """Error inesperado (500): se registra completo en la consola del servidor y se
    responde en el mismo formato JSON que el resto, con una pista de qué revisar.
    (Para producción convendría ocultar `detail`.)"""
    logger.exception("Error no controlado en %s %s", request.method, request.url.path)
    detail = f"{type(exc).__name__}: {exc}"[:300]
    return JSONResponse(
        status_code=500,
        content={
            "success": False,
            "error": "Error interno del servidor",
            "detail": detail,
            "hint": _hint(detail),
            "data": None,
        },
    )
