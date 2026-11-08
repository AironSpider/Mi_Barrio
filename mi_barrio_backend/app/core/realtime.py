"""Conexiones WebSocket abiertas, para avisar al instante (chat de favores).

Vive en memoria: el backend corre en UN proceso (ver docker-entrypoint.sh).
Si algún día se escala a varios procesos, esto pasa a Redis pub/sub.
"""
import asyncio
import logging
import uuid
from collections import defaultdict

from fastapi import WebSocket

logger = logging.getLogger("mi_barrio.realtime")


class RealtimeHub:
    """Conexiones WebSocket abiertas por usuario (para el chat en vivo). Vive en memoria del proceso."""
    def __init__(self) -> None:
        self._sockets: dict[uuid.UUID, set[WebSocket]] = defaultdict(set)
        self._lock = asyncio.Lock()

    async def connect(self, user_id: uuid.UUID, websocket: WebSocket) -> None:
        """Registra un WebSocket abierto del usuario."""
        async with self._lock:
            self._sockets[user_id].add(websocket)

    async def disconnect(self, user_id: uuid.UUID, websocket: WebSocket) -> None:
        """Quita el WebSocket del usuario; si no le quedan, deja de figurar en línea."""
        async with self._lock:
            sockets = self._sockets.get(user_id)
            if sockets is None:
                return
            sockets.discard(websocket)
            if not sockets:
                self._sockets.pop(user_id, None)

    def is_online(self, user_id: uuid.UUID) -> bool:
        """True si el usuario tiene al menos una conexión abierta."""
        return bool(self._sockets.get(user_id))

    async def send(self, user_ids: set[uuid.UUID], payload: dict) -> None:
        """Envía a todos los teléfonos abiertos de esos usuarios. Un socket caído
        se descarta sin afectar a los demás."""
        async with self._lock:
            targets = [(uid, ws) for uid in user_ids for ws in self._sockets.get(uid, ())]
        dead = []
        for uid, ws in targets:
            try:
                await ws.send_json(payload)
            except Exception:  # noqa: BLE001 - conexión cerrada a medias
                dead.append((uid, ws))
        for uid, ws in dead:
            await self.disconnect(uid, ws)


hub = RealtimeHub()
