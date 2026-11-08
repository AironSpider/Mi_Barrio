from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.exceptions import RequestValidationError
from sqlalchemy import text
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.core import log_redaction
from app.core.database import engine
from app.core.exceptions import (
    custom_http_exception_handler,
    unhandled_exception_handler,
    validation_exception_handler,
)
from app.core.tenant_middleware import TenantMiddleware

from app.features.sync_engine.router import router as sync_router
from app.features.solidarity_network.router import router as solidarity_router
from app.features.chat.router import realtime_router, router as chat_router
from app.features.proximity_services.router import endorsement_router, router as services_router
from app.features.emergency_support.router import router as emergency_router
from app.features.moderation.router import (
    platform_router as platform_reports_router,
    router as moderation_router,
)
from app.features.auth_barrio.router import router as tenants_router
from app.features.auth_barrio.profile_router import router as profile_router
from app.features.auth_barrio.account_router import router as account_router
from app.features.auth_barrio.auth_router import (
    platform_router,
    router as auth_router,
)

# Los tokens del chat viajan en la URL del WebSocket: no deben quedar en los logs.
log_redaction.install()

app = FastAPI(
    title="Mi Barrio API - Backend Resiliente",
    description="Backend Multi-Tenant Offline-First para la Hackathon de El Comercio",
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.add_middleware(TenantMiddleware)

app.add_exception_handler(StarletteHTTPException, custom_http_exception_handler)
app.add_exception_handler(RequestValidationError, validation_exception_handler)
app.add_exception_handler(Exception, unhandled_exception_handler)

app.include_router(sync_router)
app.include_router(solidarity_router)
app.include_router(chat_router)
app.include_router(realtime_router)
app.include_router(services_router)
app.include_router(endorsement_router)
app.include_router(emergency_router)
app.include_router(moderation_router)
app.include_router(platform_reports_router)
app.include_router(tenants_router)
app.include_router(profile_router)
app.include_router(auth_router)
app.include_router(account_router)
app.include_router(platform_router)


@app.get("/health/live", tags=["System"])
async def liveness_check():
    """Liveness probe that does not wake the external PostgreSQL database."""
    return {"status": "alive"}


def _expected_migration() -> str | None:
    """Última migración del repo (head de Alembic)."""
    try:
        from alembic.config import Config
        from alembic.script import ScriptDirectory

        ini = Path(__file__).resolve().parent.parent / "alembic.ini"
        return ScriptDirectory.from_config(Config(str(ini))).get_current_head()
    except Exception:
        return None


EXPECTED_MIGRATION = _expected_migration()


@app.get("/health", tags=["System"])
async def health_check():
    """Comprueba de verdad la base de datos y si faltan migraciones."""
    db_status, db_migration, hint = "ok", None, None
    try:
        async with engine.connect() as conn:
            await conn.execute(text("SELECT 1"))
            db_migration = (await conn.execute(text("SELECT version_num FROM alembic_version"))).scalar()
    except Exception as exc:
        db_status = f"error: {type(exc).__name__}: {exc}"[:200]
        hint = "Revisa que PostgreSQL esté encendido y la variable DATABASE_URL (usuario y contraseña)."

    migrations_ok = db_migration is not None and db_migration == EXPECTED_MIGRATION
    if db_status == "ok" and not migrations_ok:
        hint = "Faltan migraciones: ejecuta `alembic upgrade head`."

    healthy = db_status == "ok" and migrations_ok
    return {
        "success": healthy,
        "error": None if healthy else hint,
        "data": {
            "status": "online",
            "system": "Mi Barrio API",
            "db_connection": "active" if db_status == "ok" else db_status,
            "db_migration": db_migration,
            "expected_migration": EXPECTED_MIGRATION,
            "migrations_up_to_date": migrations_ok,
        },
    }
