"""Esquemas (Pydantic) del push y pull de sincronización."""
from pydantic import BaseModel, ConfigDict, Field
from typing import List, Dict, Any, Optional
from datetime import datetime

class MutationItem(BaseModel):
    """Un cambio hecho en el celular: tabla, id del registro, operación (UPSERT o DELETE) y sus datos (el payload lleva updated_at para LWW)."""
    target_table: str
    record_id: str
    operation: str = Field(..., pattern="^(UPSERT|DELETE)$")
    payload: Dict[str, Any]

class SyncPushRequest(BaseModel):
    # Ejemplo listo para "Try it out" en Swagger (un post creado sin internet).
    """Lote de cambios que sube la app."""
    model_config = ConfigDict(json_schema_extra={"examples": [{
        "client_sync_timestamp": "2026-11-07T15:00:00Z",
        "mutations": [{
            "target_table": "solidarity_posts",
            "record_id": "7b8f9a2e-4b71-4d3e-908a-2c8b5e9f1a3d",
            "operation": "UPSERT",
            "payload": {
                "id": "7b8f9a2e-4b71-4d3e-908a-2c8b5e9f1a3d",
                "author_user_id": "5f3a2c1b-1234-4abc-9def-0123456789ab",
                "flow_type": "SOLICITO_AYUDA",
                "modality": "PRESTAMO_HERRAMIENTA",
                "title": "Préstamo de escalera",
                "description": "Para reparar la canaleta",
                "is_emergency_context": False,
                "status": "DISPONIBLE",
                "lat": -5.1945,
                "lng": -80.6328,
                "is_deleted": False,
                "updated_at": "2026-11-07T14:58:00Z",
            },
        }],
    }]})

    client_sync_timestamp: datetime
    mutations: List[MutationItem]

class RejectedMutation(BaseModel):
    """Un cambio que el servidor no aceptó y por qué."""
    record_id: str
    target_table: str
    reason: str

class SyncPushResponse(BaseModel):
    """Resultado del push: cuántos se aplicaron, cuáles no y la hora del servidor."""
    success: bool
    processed_count: int
    server_timestamp: datetime
    processed_record_ids: List[str]
    # Mutaciones que NO se guardaron y por qué (quedan en la cola del celular).
    rejected: List[RejectedMutation] = []

class TenantInfo(BaseModel):
    """Estado del barrio que viaja en cada pull (la app lo usa para el Modo Emergencia)."""
    id: str
    name: Optional[str] = None
    is_emergency_active: bool = False
    registered: bool = False  # False si el barrio no existe en la tabla tenants

class SyncPullResponse(BaseModel):
    """Cambios del barrio desde la última vez (delta por tabla), datos del barrio y si hay más páginas."""
    server_timestamp: datetime
    has_more: bool
    tenant: Optional[TenantInfo] = None
    delta: Dict[str, List[Dict[str, Any]]]