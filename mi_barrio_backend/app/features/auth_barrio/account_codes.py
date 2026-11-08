"""Códigos de 6 dígitos por correo: verificar el correo y recuperar la contraseña."""
from __future__ import annotations

import hashlib
import hmac
import os
import secrets
import uuid
from datetime import datetime, timedelta, timezone

from fastapi import HTTPException, status
from sqlalchemy import func, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core import email_sender
from app.features.auth_barrio.models import AuthCode

PURPOSE_VERIFY = "VERIFY_EMAIL"
PURPOSE_RESET = "RESET_PASSWORD"

CODE_TTL = timedelta(minutes=15)
MAX_ATTEMPTS = 5
RESEND_AFTER = timedelta(seconds=60)
MAX_PER_HOUR = 5


def debug_codes_enabled() -> bool:
    """Solo para pruebas locales: devuelve el código en la respuesta.

    Requiere AUTH_DEBUG_CODES=1 Y que el correo NO esté configurado, así que en
    producción (con SMTP) nunca se activa aunque alguien deje la variable puesta.
    """
    return os.getenv("AUTH_DEBUG_CODES") == "1" and not email_sender.is_configured()


def _pepper() -> bytes:
    return (os.getenv("MI_BARRIO_JWT_SECRET") or "solo-desarrollo").encode("utf-8")


def _hash(email: str, purpose: str, code: str) -> str:
    message = f"{purpose}:{email}:{code}".encode("utf-8")
    return hmac.new(_pepper(), message, hashlib.sha256).hexdigest()


def _now() -> datetime:
    return datetime.now(timezone.utc)


async def issue_code(db: AsyncSession, email: str, purpose: str) -> str:
    """Crea un código nuevo (invalida los anteriores) y lo devuelve.

    Lanza 429 si se pidió hace menos de 60 s o más de 5 veces en una hora.
    """
    now = _now()
    last = await db.scalar(
        select(func.max(AuthCode.created_at)).where(
            AuthCode.email == email, AuthCode.purpose == purpose
        )
    )
    if last is not None and now - last < RESEND_AFTER:
        wait = int((RESEND_AFTER - (now - last)).total_seconds()) + 1
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=f"Espera {wait} s antes de pedir otro código.",
            headers={"Retry-After": str(wait)},
        )
    recent = await db.scalar(
        select(func.count(AuthCode.id)).where(
            AuthCode.email == email,
            AuthCode.purpose == purpose,
            AuthCode.created_at > now - timedelta(hours=1),
        )
    )
    if (recent or 0) >= MAX_PER_HOUR:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Pediste muchos códigos. Vuelve a intentar en una hora.",
            headers={"Retry-After": "3600"},
        )
    await db.execute(
        update(AuthCode)
        .where(
            AuthCode.email == email,
            AuthCode.purpose == purpose,
            AuthCode.used_at.is_(None),
        )
        .values(used_at=now)
    )
    code = f"{secrets.randbelow(1_000_000):06d}"
    db.add(
        AuthCode(
            id=uuid.uuid4(),
            email=email,
            purpose=purpose,
            code_hash=_hash(email, purpose, code),
            expires_at=now + CODE_TTL,
            created_at=now,
        )
    )
    await db.flush()
    return code


async def consume_code(db: AsyncSession, email: str, purpose: str, code: str) -> None:
    """Marca el código como usado. Lanza 400 si no es válido, venció o se agotó."""
    wrong = HTTPException(
        status_code=status.HTTP_400_BAD_REQUEST,
        detail="El código no es correcto o ya venció. Revisa el correo o pide uno nuevo.",
    )
    now = _now()
    current = await db.scalar(
        select(AuthCode)
        .where(
            AuthCode.email == email,
            AuthCode.purpose == purpose,
            AuthCode.used_at.is_(None),
        )
        .order_by(AuthCode.created_at.desc())
        .limit(1)
        .with_for_update()
    )
    if current is None or current.expires_at <= now or current.attempts >= MAX_ATTEMPTS:
        raise wrong
    if not hmac.compare_digest(current.code_hash, _hash(email, purpose, code.strip())):
        current.attempts += 1
        if current.attempts >= MAX_ATTEMPTS:
            current.used_at = now
        await db.commit()
        raise wrong
    current.used_at = now
