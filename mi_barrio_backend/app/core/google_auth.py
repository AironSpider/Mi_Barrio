"""Verificación del "ID token" que entrega Google Sign-In en el celular.

El celular inicia sesión con Google y manda al servidor un ID token (un JWT
firmado por Google). Aquí se valida con el endpoint oficial `tokeninfo` de
Google (sin dependencias extra) y se comprueba:
- que el token es para NUESTRA app (`aud` = el Web client ID del proyecto),
- que lo emitió Google (`iss`),
- que no venció (`exp`),
- y que Google ya verificó el correo (`email_verified`).

Variable de entorno (Render → Environment):
    GOOGLE_CLIENT_IDS  el "Web client ID" (…apps.googleusercontent.com).
                       Puede ser una lista separada por comas.
"""
from __future__ import annotations

import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass

from fastapi import HTTPException, status
from starlette.concurrency import run_in_threadpool

TOKENINFO_URL = "https://oauth2.googleapis.com/tokeninfo"
VALID_ISSUERS = {"accounts.google.com", "https://accounts.google.com"}


@dataclass(frozen=True)
class GoogleIdentity:
    """Lo que Google confirma de la persona: su id interno (sub), su correo verificado y su nombre."""
    sub: str
    email: str
    name: str


def allowed_client_ids() -> set[str]:
    """Client IDs de Google aceptados (variable GOOGLE_CLIENT_IDS, separados por comas)."""
    raw = os.getenv("GOOGLE_CLIENT_IDS", "")
    return {part.strip() for part in raw.split(",") if part.strip()}


def _fetch_tokeninfo(id_token: str) -> dict:
    url = TOKENINFO_URL + "?" + urllib.parse.urlencode({"id_token": id_token})
    try:
        with urllib.request.urlopen(url, timeout=10) as response:
            return json.loads(response.read().decode())
    except urllib.error.HTTPError as exc:
        if exc.code in (400, 401):
            return {}
        raise


def identity_from_claims(claims: dict, client_ids: set[str], now: float | None = None) -> GoogleIdentity:
    """Valida los datos que devolvió Google. Lanza 401 si algo no cuadra."""
    def invalid(reason: str) -> HTTPException:
        """Error 401 con un motivo corto para mostrar en la app."""
        return HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"No pudimos confirmar tu cuenta de Google ({reason}). Intenta de nuevo.",
        )

    if not claims:
        raise invalid("token inválido")
    if claims.get("aud") not in client_ids:
        raise invalid("la app no coincide")
    if claims.get("iss") not in VALID_ISSUERS:
        raise invalid("emisor desconocido")
    try:
        expires = int(claims.get("exp", 0))
    except (TypeError, ValueError):
        expires = 0
    if expires <= (now if now is not None else time.time()):
        raise invalid("el token venció")
    if str(claims.get("email_verified", "")).lower() != "true":
        raise invalid("Google no verificó ese correo")
    sub = str(claims.get("sub") or "")
    email = str(claims.get("email") or "").strip().lower()
    if not sub or not email:
        raise invalid("faltan datos")
    name = str(claims.get("name") or email.split("@")[0]).strip()[:150]
    return GoogleIdentity(sub=sub, email=email, name=name)


async def verify_google_id_token(id_token: str) -> GoogleIdentity:
    """Valida el ID token con Google (tokeninfo) y devuelve la identidad. 503 si GOOGLE_CLIENT_IDS no está configurado; 401 si el token no sirve."""
    client_ids = allowed_client_ids()
    if not client_ids:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Entrar con Google todavía no está disponible. Usa tu correo y contraseña.",
        )
    try:
        claims = await run_in_threadpool(_fetch_tokeninfo, id_token)
    except Exception as exc:  # noqa: BLE001 - red caída hacia Google
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="No pudimos comunicarnos con Google. Intenta de nuevo en un momento.",
        ) from exc
    return identity_from_claims(claims, client_ids)
