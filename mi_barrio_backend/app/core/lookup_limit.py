"""Límite de consultas públicas por IP (en memoria), para que no se puedan
adivinar códigos de barrio probando miles de combinaciones."""
import threading
import time
from collections import defaultdict, deque

from fastapi import HTTPException, status

WINDOW_SECONDS = 300
MAX_PER_IP = 30

_lock = threading.Lock()
_by_ip: dict[str, deque[float]] = defaultdict(deque)


def check_and_count(ip: str) -> None:
    """Cuenta una consulta; lanza 429 si la IP superó el límite de la ventana."""
    now = time.monotonic()
    with _lock:
        bucket = _by_ip[ip]
        while bucket and now - bucket[0] > WINDOW_SECONDS:
            bucket.popleft()
        if len(bucket) >= MAX_PER_IP:
            retry = int(WINDOW_SECONDS - (now - bucket[0])) + 1
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="Demasiadas consultas. Espera unos minutos e intenta de nuevo.",
                headers={"Retry-After": str(retry)},
            )
        bucket.append(now)


def reset() -> None:
    """Solo para pruebas."""
    with _lock:
        _by_ip.clear()
