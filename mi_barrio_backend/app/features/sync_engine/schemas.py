from pydantic import BaseModel, Field
from typing import List, Dict, Any, Optional
from datetime import datetime

class MutationItem(BaseModel):
    target_table: str
    record_id: str
    operation: str = Field(..., pattern="^(UPSERT|DELETE)$")
    payload: Dict[str, Any]

class SyncPushRequest(BaseModel):
    client_sync_timestamp: datetime
    mutations: List[MutationItem]

class SyncPushResponse(BaseModel):
    success: bool
    processed_count: int
    server_timestamp: datetime
    processed_record_ids: List[str]

class SyncPullResponse(BaseModel):
    server_timestamp: datetime
    has_more: bool
    delta: Dict[str, List[Dict[str, Any]]]