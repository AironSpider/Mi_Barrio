"""Límite de intentos fallidos de login (en memoria, suficiente para la hackathon).

- Máximo 5 fallos por correo + IP en 5 minutos.
- Máximo 30 fallos por IP en 5 minutos (evita probar muchos correos).
Al iniciar sesión bien, se limpia el contador de ese correo + IP.
"""
import threading
import time
from collections import defaultdict, deque

WINDOW_SECONDS = 300
MAX_PER_ACCOUNT = 5
MAX_PER_IP = 30

_lock = threading.Lock()
_by_account: dict[tuple[str, str], deque[float]] = defaultdict(deque)
_by_ip: dict[str, deque[float]] = defaultdict(deque)


def _trim(bucket: deque[float], now: float) -> None:
    while bucket and now - bucket[0] > WINDOW_SECONDS:
        bucket.popleft()


def retry_after(email: str, ip: str) -> int:
    """Segundos de espera si está bloqueado; 0 si puede intentar."""
    now = time.monotonic()
    with _lock:
        account = _by_account[(email, ip)]
        per_ip = _by_ip[ip]
        _trim(account, now)
        _trim(per_ip, now)
        waits = []
        if len(account) >= MAX_PER_ACCOUNT:
            waits.append(WINDOW_SECONDS - (now - account[0]))
        if len(per_ip) >= MAX_PER_IP:
            waits.append(WINDOW_SECONDS - (now - per_ip[0]))
        return int(max(waits)) + 1 if waits else 0


def register_failure(email: str, ip: str) -> None:
    """Anota un intento fallido (contraseña o código) para ese correo e IP."""
    now = time.monotonic()
    with _lock:
        _by_account[(email, ip)].append(now)
        _by_ip[ip].append(now)


def register_success(email: str, ip: str) -> None:
    """Borra los intentos fallidos de ese correo e IP tras un acceso correcto."""
    with _lock:
        _by_account.pop((email, ip), None)
