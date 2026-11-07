from pydantic import BaseModel, ConfigDict, Field
from typing import List, Dict, Any, Optional
from datetime import datetime

class MutationItem(BaseModel):
    target_table: str
    record_id: str
    operation: str = Field(..., pattern="^(UPSERT|DELETE)$")
    payload: Dict[str, Any]

class SyncPushRequest(BaseModel):
    # Ejemplo listo para "Try it out" en Swagger (un post creado sin internet).
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
    record_id: str
    target_table: str
    reason: str

class SyncPushResponse(BaseModel):
    success: bool
    processed_count: int
    server_timestamp: datetime
    processed_record_ids: List[str]
    # Mutaciones que NO se guardaron y por qué (quedan en la cola del celular).
    rejected: List[RejectedMutation] = []

class SyncPullResponse(BaseModel):
    server_timestamp: datetime
    has_more: bool
    delta: Dict[str, List[Dict[str, Any]]]