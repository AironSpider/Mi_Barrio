"""Formato común de errores de la API: {"success": false, "error": ..., "data": null}."""
import logging
import os

from fastapi import Request
from fastapi.responses import JSONResponse
from fastapi.exceptions import RequestValidationError
from starlette.exceptions import HTTPException as StarletteHTTPException

logger = logging.getLogger("mi_barrio.errors")

async def custom_http_exception_handler(request: Request, exc: StarletteHTTPException):
    """Convierte cualquier HTTPException al formato común de la API: {"success": false, "error": "...", "data": null}."""
    return JSONResponse(
        status_code=exc.status_code,
        content={"success": False, "error": exc.detail, "data": None},
    )

async def validation_exception_handler(request: Request, exc: RequestValidationError):
    """Errores de validación (422) en el formato común, con un mensaje simple y el detalle por campo."""
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


def _show_error_details() -> bool:
    """En Render (producción) se ocultan los detalles técnicos; en una PC se muestran.

    Render define la variable RENDER. API_DEBUG_ERRORS=1 los muestra igual.
    """
    if os.getenv("API_DEBUG_ERRORS") == "1":
        return True
    return not os.getenv("RENDER")


async def unhandled_exception_handler(request: Request, exc: Exception):
    """Error inesperado (500): se registra completo en los logs del servidor.

    Al vecino le llega un mensaje simple. El detalle técnico (tipo de error, SQL)
    y la pista de qué revisar solo se envían fuera de producción: en producción
    revelarían cómo está hecha la base de datos y la app los mostraría tal cual.
    """
    logger.exception("Error no controlado en %s %s", request.method, request.url.path)
    content = {
        "success": False,
        "error": "Algo falló en el servidor. Intenta de nuevo en un momento.",
        "data": None,
    }
    if _show_error_details():
        detail = f"{type(exc).__name__}: {exc}"[:300]
        content["detail"] = detail
        content["hint"] = _hint(detail)
    return JSONResponse(status_code=500, content=content)
