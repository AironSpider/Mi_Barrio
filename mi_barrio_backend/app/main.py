from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.exceptions import RequestValidationError
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.features.sync_engine.router import router as sync_router
from app.core.exceptions import custom_http_exception_handler, validation_exception_handler

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

# Registrar manejadores de errores globales
app.add_exception_handler(StarletteHTTPException, custom_http_exception_handler)
app.add_exception_handler(RequestValidationError, validation_exception_handler)

app.include_router(sync_router)

@app.get("/health", tags=["System"])
def health_check():
    return {
        "success": True,
        "error": None,
        "data": {
            "status": "online", 
            "system": "Mi Barrio API",
            "db_connection": "active"
        }
    }