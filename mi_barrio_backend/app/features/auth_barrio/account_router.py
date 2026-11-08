"""Cuentas reales: verificar el correo, recuperar la contraseña y entrar con Google.

Todas estas rutas son públicas (no piden sesión ni X-Tenant-ID) y nunca revelan
si un correo está registrado: pedir un código para un correo que no existe
responde igual que para uno que sí.
"""
from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core import email_sender, google_auth, rate_limit
from app.core.database import get_db_session
from app.features.auth_barrio import account_codes
from app.features.auth_barrio.auth_router import (
    _auth_response,
    _client_ip,
    _hash,
    _too_many_attempts,
)
from app.features.auth_barrio.models import PlatformAdmin, Tenant, User
from app.features.auth_barrio.schemas import (
    AuthResponse,
    CodeSentResponse,
    EmailRequest,
    GoogleLoginRequest,
    ResetPasswordRequest,
    SetPasswordRequest,
    VerifyEmailRequest,
)

router = APIRouter(prefix="/api/v1/auth", tags=["Cuentas reales"])

PUBLIC_PATHS = {
    "/api/v1/auth/email/send-code",
    "/api/v1/auth/email/verify",
    "/api/v1/auth/password/forgot",
    "/api/v1/auth/password/reset",
    "/api/v1/auth/google",
}

NEEDS_NEIGHBORHOOD = "NEEDS_JOIN_CODE"


async def _active_user(db: AsyncSession, email: str) -> User | None:
    return await db.scalar(
        select(User).where(User.email == email, User.is_deleted.is_(False))
    )


async def _tenant_or_403(db: AsyncSession, user: User) -> Tenant:
    tenant = await db.get(Tenant, user.tenant_id)
    if tenant is None:
        raise HTTPException(status_code=403, detail="La cuenta ya no pertenece a un barrio activo")
    return tenant


def _sent(message: str, code: str | None) -> CodeSentResponse:
    return CodeSentResponse(
        message=message,
        debug_code=code if account_codes.debug_codes_enabled() else None,
    )


# ─────────────────────────── Verificar el correo ───────────────────────────
@router.post("/email/send-code", response_model=CodeSentResponse)
async def send_verification_code(payload: EmailRequest, db: AsyncSession = Depends(get_db_session)):
    email = payload.email.lower()
    user = await _active_user(db, email)
    message = "Si la cuenta existe, te enviamos un código al correo."
    if user is None or user.email_verified:
        return _sent(message, None)
    code = await account_codes.issue_code(db, email, account_codes.PURPOSE_VERIFY)
    await db.commit()
    await email_sender.send_verification_code(email, user.full_name, code)
    return _sent(message, code)


@router.post("/email/verify", response_model=AuthResponse)
async def verify_email(
    payload: VerifyEmailRequest,
    request: Request,
    db: AsyncSession = Depends(get_db_session),
):
    email = payload.email.lower()
    ip = _client_ip(request)
    wait = rate_limit.retry_after(email, ip)
    if wait:
        raise _too_many_attempts(wait)
    user = await _active_user(db, email)
    if user is None:
        rate_limit.register_failure(email, ip)
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El código no es correcto o ya venció. Revisa el correo o pide uno nuevo.",
        )
    if not user.email_verified:
        try:
            await account_codes.consume_code(db, email, account_codes.PURPOSE_VERIFY, payload.code)
        except HTTPException:
            rate_limit.register_failure(email, ip)
            raise
        user.email_verified = True
        await db.commit()
        await db.refresh(user)
    rate_limit.register_success(email, ip)
    return _auth_response(user, await _tenant_or_403(db, user))


# ─────────────────────────── Recuperar contraseña ───────────────────────────
@router.post("/password/forgot", response_model=CodeSentResponse)
async def forgot_password(payload: EmailRequest, db: AsyncSession = Depends(get_db_session)):
    email = payload.email.lower()
    message = "Si hay una cuenta con ese correo, te enviamos un código para cambiar la contraseña."
    user = await _active_user(db, email)
    if user is None:
        return _sent(message, None)
    code = await account_codes.issue_code(db, email, account_codes.PURPOSE_RESET)
    await db.commit()
    await email_sender.send_password_reset_code(email, user.full_name, code)
    return _sent(message, code)


@router.post("/password/reset", response_model=AuthResponse)
async def reset_password(
    payload: ResetPasswordRequest,
    request: Request,
    db: AsyncSession = Depends(get_db_session),
):
    email = payload.email.lower()
    ip = _client_ip(request)
    wait = rate_limit.retry_after(email, ip)
    if wait:
        raise _too_many_attempts(wait)
    user = await _active_user(db, email)
    if user is None:
        rate_limit.register_failure(email, ip)
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="El código no es correcto o ya venció. Revisa el correo o pide uno nuevo.",
        )
    try:
        await account_codes.consume_code(db, email, account_codes.PURPOSE_RESET, payload.code)
    except HTTPException:
        rate_limit.register_failure(email, ip)
        raise
    user.password_hash = await _hash(payload.new_password)
    user.email_verified = True  # demostró que el correo es suyo
    await db.commit()
    await db.refresh(user)
    rate_limit.register_success(email, ip)
    return _auth_response(user, await _tenant_or_403(db, user))


@router.post("/password/set", response_model=AuthResponse)
async def set_password(
    payload: SetPasswordRequest,
    request: Request,
    db: AsyncSession = Depends(get_db_session),
):
    """Quien entró con Google crea su contraseña (pide sesión iniciada).

    Solo sirve si la cuenta todavía no tiene contraseña: para cambiar una que
    ya existe se usa "Olvidé mi contraseña" (con el código del correo).
    """
    claims = getattr(request.state, "auth_claims", None)
    if claims is None or claims.get("role") == "SUPER_ADMIN":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Se requiere una sesión Bearer",
            headers={"WWW-Authenticate": "Bearer"},
        )
    user = await db.scalar(
        select(User).where(User.id == uuid.UUID(claims["sub"]), User.is_deleted.is_(False))
    )
    if user is None:
        raise HTTPException(status_code=401, detail="La sesión ya no es válida")
    if user.password_hash is not None:
        raise HTTPException(
            status_code=409,
            detail="Tu cuenta ya tiene contraseña. Para cambiarla usa \"¿Olvidaste tu contraseña?\".",
        )
    user.password_hash = await _hash(payload.password)
    await db.commit()
    await db.refresh(user)
    return _auth_response(user, await _tenant_or_403(db, user))


# ─────────────────────────── Entrar con Google ───────────────────────────
async def google_login(
    db: AsyncSession, identity: google_auth.GoogleIdentity, payload: GoogleLoginRequest
) -> AuthResponse:
    """Entra o crea la cuenta con una identidad de Google ya verificada."""
    is_admin = await db.scalar(
        select(PlatformAdmin.id).where(PlatformAdmin.email == identity.email)
    )
    if is_admin is not None:
        raise HTTPException(
            status_code=403,
            detail="El superadministrador entra con correo y contraseña.",
        )

    user = await db.scalar(
        select(User).where(User.google_sub == identity.sub, User.is_deleted.is_(False))
    )
    if user is None:
        user = await _active_user(db, identity.email)
        if user is not None:
            # Ya tenía cuenta con ese correo: se vincula su Google.
            user.google_sub = identity.sub
            user.email_verified = True
            await db.commit()
            await db.refresh(user)
    if user is not None:
        if not user.email_verified:
            user.email_verified = True
            await db.commit()
            await db.refresh(user)
        return _auth_response(user, await _tenant_or_403(db, user))

    # Cuenta nueva: hace falta saber a qué barrio entra.
    if not payload.join_code:
        raise HTTPException(status_code=status.HTTP_428_PRECONDITION_REQUIRED, detail=NEEDS_NEIGHBORHOOD)
    tenant = await db.scalar(
        select(Tenant).where(Tenant.join_code == payload.join_code.strip().upper())
    )
    if tenant is None:
        raise HTTPException(status_code=404, detail="No encontramos un barrio con ese código")
    user = User(
        id=uuid.uuid4(),
        tenant_id=tenant.id,
        full_name=identity.name or identity.email.split("@")[0],
        email=identity.email,
        password_hash=None,  # la app le pide crear una contraseña enseguida (/password/set)
        google_sub=identity.sub,
        email_verified=True,
        role=payload.role,
        is_approved=True,
        phone="",
        home_lat=tenant.center_lat,
        home_lng=tenant.center_lng,
        tutorial_completed=False,
    )
    db.add(user)
    try:
        await db.commit()
    except IntegrityError as exc:
        await db.rollback()
        raise HTTPException(status_code=409, detail="Ya existe una cuenta con ese correo") from exc
    await db.refresh(user)
    return _auth_response(user, tenant)


@router.post("/google", response_model=AuthResponse)
async def login_with_google(payload: GoogleLoginRequest, db: AsyncSession = Depends(get_db_session)):
    identity = await google_auth.verify_google_id_token(payload.id_token)
    return await google_login(db, identity, payload)
