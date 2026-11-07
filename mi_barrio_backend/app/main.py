from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.features.sync_engine.router import router as sync_router

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

app.include_router(sync_router)

@app.get("/health")
def health_check():
    return {"status": "ok", "system": "Mi Barrio Backend Online"}