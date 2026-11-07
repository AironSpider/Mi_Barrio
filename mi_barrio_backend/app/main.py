from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.exceptions import RequestValidationError
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.core.exceptions import custom_http_exception_handler, validation_exception_handler
from app.core.tenant_middleware import TenantMiddleware

from app.features.sync_engine.router import router as sync_router
from app.features.solidarity_network.router import router as solidarity_router
from app.features.proximity_services.router import router as services_router
from app.features.emergency_support.router import router as emergency_router

logger = logging.getLogger(__name__)

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
app.include_router(services_router)
app.include_router(emergency_router)


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
def health_check():
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
