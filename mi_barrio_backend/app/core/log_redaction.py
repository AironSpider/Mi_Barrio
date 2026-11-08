"""Quita el token de sesión de los logs.

El chat en tiempo real se conecta con `?token=...` en la URL (los WebSocket del
celular no mandan encabezados) y uvicorn escribe esa URL en los logs de Render.
Con el token cualquiera que lea los logs podría entrar como ese vecino. Este
filtro lo cambia por `token=***` antes de escribir la línea.
"""
from __future__ import annotations

import logging
import re

_TOKEN = re.compile(r"(token=)[^&\s\"']+", re.IGNORECASE)


class RedactTokens(logging.Filter):
    """Filtro de logging que reemplaza token=... por token=*** en cada línea."""
    def filter(self, record: logging.LogRecord) -> bool:
        """Censura el token en el mensaje y deja pasar la línea (nunca la descarta)."""
        message = record.getMessage()
        if "token=" in message.lower():
            record.msg = _TOKEN.sub(r"\1***", message)
            record.args = ()
        return True


def install() -> None:
    """Agrega el filtro a los loggers de uvicorn (una sola vez). Se llama al iniciar la app."""
    for name in ("uvicorn.access", "uvicorn.error", "uvicorn"):
        logger = logging.getLogger(name)
        if not any(isinstance(f, RedactTokens) for f in logger.filters):
            logger.addFilter(RedactTokens())
