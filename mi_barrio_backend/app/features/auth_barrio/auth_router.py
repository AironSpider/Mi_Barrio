"""Cuentas: registro, login, sesión actual y gestión de barrios del superadministrador."""
import uuid
from datetime import datetime, timezone
import secrets

from fastapi import APIRouter, Depends, HTTPException, Request, status
from starlette.concurrency import run_in_threadpool
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.exc import IntegrityError

from app.core import email_sender, email_validation, rate_limit
from app.core.auth_security import create_access_token, hash_password, verify_password
from app.core.database import get_db_session
from app.core.tenant_middleware import require_role
from app.features.auth_barrio import account_codes
from app.features.auth_barrio.models import PlatformAdmin, Tenant, User
from app.shared.contract_values import TERMS_VERSION
from app.features.auth_barrio.schemas import (
    AuthResponse,
    AuthUserResponse,
    LoginRequest,
    NeighborhoodAdminCreate,
    NeighborhoodAdminCreated,
    RegisterRequest,
    TenantResponse,
)

router = APIRouter(prefix="/api/v1/auth", tags=["Authentication"])

# Hash ficticio: se verifica contra él cuando el correo no existe, para que el tiempo
# de respuesta no revele qué correos están registrados.
_DUMMY_HASH: str | None = None


async def _hash(password: str) -> str:
    # PBKDF2 (310 000 iteraciones) en un hilo aparte: no congela al resto de pedidos.
    return await run_in_threadpool(hash_password, password)


async def _verify(password: str, stored_hash: str | None) -> bool:
    global _DUMMY_HASH
    if stored_hash is None:
        if _DUMMY_HASH is None:
            _DUMMY_HASH = await _hash("contrasena-ficticia-para-tiempo-constante")
        await run_in_threadpool(verify_password, password, _DUMMY_HASH)
        return False
    return await run_in_threadpool(verify_password, password, stored_hash)


def _client_ip(request: Request) -> str:
    return request.client.host if request.client else "desconocida"


def _too_many_attempts(seconds: int) -> HTTPException:
    minutes = max(1, round(seconds / 60))
    return HTTPException(
        status_code=status.HTTP_429_TOO_MANY_REQUESTS,
        detail=f"Demasiados intentos fallidos. Vuelve a intentar en {minutes} min.",
        headers={"Retry-After": str(seconds)},
    )


TERMS_REQUIRED = (
    "Para crear tu cuenta debes aceptar los Términos y condiciones, la "
    "Política de privacidad y las Normas de la comunidad."
)


def require_terms(accepted: bool) -> None:
    """Sin la casilla marcada no se crea ninguna cuenta (ni con Google)."""
    if not accepted:
        raise HTTPException(status_code=422, detail=TERMS_REQUIRED)


def stamp_terms(user: User) -> None:
    user.terms_accepted_at = datetime.now(timezone.utc)
    user.terms_version = TERMS_VERSION


async def ensure_not_suspended(db: AsyncSession, user: User) -> None:
    """Cuenta suspendida por reportes: no entra y se le dice con quién hablar."""
    if not user.is_suspended:
        return
    from app.features.moderation import service as moderation

    names = await moderation.admin_names(db, user.tenant_id)
    raise HTTPException(status_code=403, detail=moderation.suspended_message(names))


def _user_response(user: User, tenant: Tenant) -> AuthUserResponse:
    return AuthUserResponse(
        id=user.id,
        tenant_id=user.tenant_id,
        full_name=user.full_name,
        email=user.email,
        role=user.role,
        is_approved=user.is_approved,
        email_verified=user.email_verified,
        has_password=user.password_hash is not None,
        tenant=TenantResponse.model_validate(tenant),
    )


def _platform_admin_response(admin: PlatformAdmin) -> AuthUserResponse:
    """El superadministrador no pertenece a ningún barrio (tenant = None)."""
    return AuthUserResponse(
        id=admin.id,
        tenant_id=None,
        full_name=admin.full_name,
        email=admin.email,
        role="SUPER_ADMIN",
        tenant=None,
    )


def _auth_response(user: User, tenant: Tenant) -> AuthResponse:
    return AuthResponse(
        access_token=create_access_token(
            user_id=user.id,
            tenant_id=user.tenant_id,
            role=user.role,
        ),
        user=_user_response(user, tenant),
    )


@router.post("/register", response_model=AuthResponse, status_code=status.HTTP_201_CREATED)
async def register(payload: RegisterRequest, db: AsyncSession = Depends(get_db_session)):
    """Crea la cuenta (vecino o comerciante) en el barrio del código, envía el código de verificación al correo y devuelve la sesión."""
    email = payload.email.strip().lower()
    require_terms(payload.accept_terms)
    # Correos desechables, con errores de tipeo o de dominios que no existen
    # nunca recibirían el código: se rechazan antes de crear la cuenta.
    await email_validation.ensure_real_email(email)
    join_code = payload.join_code.strip().upper()
    tenant = await db.scalar(select(Tenant).where(Tenant.join_code == join_code))
    if tenant is None:
        raise HTTPException(status_code=404, detail="No encontramos un barrio con ese código")

    existing = await db.scalar(select(User).where(User.email == email))
    platform_admin = await db.scalar(
        select(PlatformAdmin.id).where(PlatformAdmin.email == email)
    )
    if platform_admin is not None or (
        existing is not None and (existing.email_verified or existing.is_deleted)
    ):
        raise HTTPException(status_code=409, detail="Ya existe una cuenta con ese correo")

    if existing is not None:
        # La cuenta nunca confirmó su correo ("Volver para cambiar datos"):
        # se reemplazan sus datos en lugar de bloquear el correo para siempre.
        user = existing
        user.tenant_id = tenant.id
        user.full_name = payload.full_name.strip()
        user.password_hash = await _hash(payload.password)
        user.role = payload.role
        user.home_lat = tenant.center_lat
        user.home_lng = tenant.center_lng
        stamp_terms(user)
    else:
        user = User(
            id=uuid.uuid4(),
            tenant_id=tenant.id,
            full_name=payload.full_name.strip(),
            email=email,
            password_hash=await _hash(payload.password),
            role=payload.role,
            is_approved=True,  # sin aprobación de la junta: publica al instante
            email_verified=False,  # se confirma con el código que llega al correo
            phone="",
            home_lat=tenant.center_lat,
            home_lng=tenant.center_lng,
            tutorial_completed=False,
        )
        stamp_terms(user)
        db.add(user)
    try:
        await db.commit()
    except IntegrityError as exc:
        await db.rollback()
        raise HTTPException(
            status_code=409,
            detail="Ya existe una cuenta con ese correo",
        ) from exc
    await db.refresh(user)
    # La respuesta se arma ANTES del código: si el código falla (p. ej. se pidió
    # otro hace menos de 60 s), el rollback no deja la cuenta sin datos.
    response = _auth_response(user, tenant)
    full_name = user.full_name
    # El código de verificación sale en segundo plano: si el correo falla,
    # la cuenta igual se crea y el vecino puede pedir otro código.
    try:
        code = await account_codes.issue_code(db, email, account_codes.PURPOSE_VERIFY)
        await db.commit()
        await email_sender.send_verification_code(email, full_name, code)
    except HTTPException:
        await db.rollback()
    return response


@router.post("/login", response_model=AuthResponse)
async def login(
    payload: LoginRequest,
    request: Request,
    db: AsyncSession = Depends(get_db_session),
):
    """Inicia sesión con correo y contraseña. Tras varios intentos fallidos pide esperar (429)."""
    email = payload.email.strip().lower()
    ip = _client_ip(request)
    wait = rate_limit.retry_after(email, ip)
    if wait:
        raise _too_many_attempts(wait)
    platform_admin = await db.scalar(
        select(PlatformAdmin).where(
            PlatformAdmin.email == email,
            PlatformAdmin.is_active.is_(True),
        )
    )
    if platform_admin is not None:
        if not await _verify(payload.password, platform_admin.password_hash):
            rate_limit.register_failure(email, ip)
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Correo o contraseña incorrectos",
                headers={"WWW-Authenticate": "Bearer"},
            )
        rate_limit.register_success(email, ip)
        return AuthResponse(
            access_token=create_access_token(
                user_id=platform_admin.id,
                tenant_id=None,
                role="SUPER_ADMIN",
            ),
            user=_platform_admin_response(platform_admin),
        )

    user = await db.scalar(
        select(User).where(User.email == email, User.is_deleted.is_(False))
    )
    if not await _verify(payload.password, user.password_hash if user else None):
        rate_limit.register_failure(email, ip)
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Correo o contraseña incorrectos",
            headers={"WWW-Authenticate": "Bearer"},
        )
    tenant = await db.get(Tenant, user.tenant_id)
    if tenant is None:
        raise HTTPException(status_code=403, detail="La cuenta ya no pertenece a un barrio activo")
    rate_limit.register_success(email, ip)
    await ensure_not_suspended(db, user)
    return _auth_response(user, tenant)


@router.get("/me", response_model=AuthUserResponse)
async def current_user(
    request: Request,
    db: AsyncSession = Depends(get_db_session),
):
    """Datos de la cuenta de la sesión actual (para restaurar la sesión al abrir la app)."""
    claims = getattr(request.state, "auth_claims", None)
    if claims is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Se requiere una sesión Bearer",
            headers={"WWW-Authenticate": "Bearer"},
        )
    user_id = uuid.UUID(claims["sub"])
    if claims.get("role") == "SUPER_ADMIN":
        admin = await db.scalar(
            select(PlatformAdmin).where(
                PlatformAdmin.id == user_id,
                PlatformAdmin.is_active.is_(True),
            )
        )
        if admin is None:
            raise HTTPException(status_code=401, detail="La sesión ya no es válida")
        return _platform_admin_response(admin)
    user = await db.scalar(
        select(User).where(User.id == user_id, User.is_deleted.is_(False))
    )
    if user is None or user.tenant_id != uuid.UUID(claims["tenant_id"]):
        raise HTTPException(status_code=401, detail="La sesión ya no es válida")
    tenant = await db.get(Tenant, user.tenant_id)
    if tenant is None:
        raise HTTPException(status_code=403, detail="El barrio de la cuenta no está disponible")
    return _user_response(user, tenant)


@router.delete("/unverified-account", status_code=status.HTTP_204_NO_CONTENT)
async def delete_unverified_account(
    request: Request,
    db: AsyncSession = Depends(get_db_session),
):
    """"Volver para cambiar datos": borra la cuenta que nunca confirmó su correo,
    así el vecino puede registrarse de nuevo (con el mismo u otro correo)."""
    claims = getattr(request.state, "auth_claims", None)
    if claims is None or claims.get("role") == "SUPER_ADMIN":
        raise HTTPException(status_code=401, detail="Se requiere una sesión Bearer")
    user = await db.get(User, uuid.UUID(claims["sub"]))
    if user is None or user.is_deleted:
        return None
    if user.email_verified:
        raise HTTPException(status_code=409, detail="Esta cuenta ya está confirmada")
    try:
        await db.delete(user)
        await db.commit()
    except IntegrityError:
        # Algo la referencia: se da de baja y se libera el correo.
        await db.rollback()
        user = await db.get(User, uuid.UUID(claims["sub"]))
        if user is not None:
            user.is_deleted = True
            user.email = None
            await db.commit()
    return None


platform_router = APIRouter(prefix="/api/v1/platform", tags=["Platform administration"])


def _new_join_code() -> str:
    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    return "MB-" + "".join(secrets.choice(alphabet) for _ in range(10))


def _is_join_code_collision(error: IntegrityError) -> bool:
    cause = error.orig
    while cause is not None:
        constraint_name = getattr(cause, "constraint_name", None)
        if constraint_name is None:
            constraint_name = getattr(
                getattr(cause, "diag", None), "constraint_name", None
            )
        if constraint_name == "ix_tenants_join_code":
            return True
        cause = getattr(cause, "orig", None)
    return False


@platform_router.post(
    "/neighborhoods",
    response_model=NeighborhoodAdminCreated,
    status_code=status.HTTP_201_CREATED,
)
async def create_neighborhood(
    payload: NeighborhoodAdminCreate,
    principal: dict = Depends(require_role(["SUPER_ADMIN"])),
    db: AsyncSession = Depends(get_db_session),
):
    """Solo superadministrador: crea un barrio (o usa uno existente por su código) y su administrador."""
    super_admin = await db.scalar(
        select(PlatformAdmin).where(
            PlatformAdmin.id == uuid.UUID(principal["sub"]),
            PlatformAdmin.is_active.is_(True),
        )
    )
    if super_admin is None:
        raise HTTPException(status_code=401, detail="La sesión ya no es válida")

    email = payload.admin_email.strip().lower()
    await email_validation.ensure_real_email(email)
    user_with_email = await db.scalar(select(User.id).where(User.email == email))
    admin_with_email = await db.scalar(
        select(PlatformAdmin.id).where(PlatformAdmin.email == email)
    )
    if user_with_email is not None or admin_with_email is not None:
        raise HTTPException(status_code=409, detail="Ya existe una cuenta con ese correo")

    if payload.join_code:
        join_code = payload.join_code.strip().upper()
        tenant = await db.scalar(select(Tenant).where(Tenant.join_code == join_code))
        if tenant is None:
            raise HTTPException(status_code=404, detail="No encontramos un barrio con ese código")
        existing_neighborhood_admin = await db.scalar(
            select(User.id).where(
                User.tenant_id == tenant.id,
                User.role == "ADMIN_BARRIO",
                User.is_deleted.is_(False),
            )
        )
        if existing_neighborhood_admin is not None:
            raise HTTPException(
                status_code=409,
                detail="Este barrio ya tiene un administrador asignado",
            )
    else:
        # El schema ya exige nombre y coordenadas cuando no viene join_code.
        tenant = None
        for _ in range(5):
            tenant = Tenant(
                id=uuid.uuid4(),
                name=(payload.neighborhood_name or "").strip(),
                join_code=_new_join_code(),
                center_lat=payload.center_lat,
                center_lng=payload.center_lng,
                is_emergency_active=False,
            )
            db.add(tenant)
            try:
                await db.flush()
                break
            except IntegrityError as exc:
                await db.rollback()
                if not _is_join_code_collision(exc):
                    raise HTTPException(
                        status_code=409,
                        detail="No se pudo crear el barrio por un conflicto de datos",
                    ) from exc
        else:
            raise HTTPException(
                status_code=503,
                detail="No se pudo generar un código de barrio único; vuelve a intentar",
            )

    neighborhood_admin = User(
        id=uuid.uuid4(),
        tenant_id=tenant.id,
        full_name=payload.admin_full_name.strip(),
        email=email,
        password_hash=await _hash(payload.admin_password),
        role="ADMIN_BARRIO",
        is_approved=True,
        phone="",
        home_lat=tenant.center_lat,
        home_lng=tenant.center_lng,
        tutorial_completed=False,
    )
    db.add(neighborhood_admin)
    try:
        await db.commit()
    except IntegrityError as exc:
        await db.rollback()
        raise HTTPException(
            status_code=409,
            detail="El correo o código de barrio ya está en uso; vuelve a intentar",
        ) from exc
    await db.refresh(tenant)
    await db.refresh(neighborhood_admin)
    return NeighborhoodAdminCreated(
        neighborhood=TenantResponse.model_validate(tenant),
        administrator=_user_response(neighborhood_admin, tenant),
    )


@platform_router.get("/neighborhoods")
async def list_neighborhoods(
    principal: dict = Depends(require_role(["SUPER_ADMIN"])),
    db: AsyncSession = Depends(get_db_session),
):
    """Solo superadministrador: lista los barrios con su código y si tienen administrador."""
    admin_counts = (
        select(User.tenant_id, func.count(User.id).label("admin_count"))
        .where(
            User.role == "ADMIN_BARRIO",
            User.is_deleted.is_(False),
        )
        .group_by(User.tenant_id)
        .subquery()
    )
    rows = (await db.execute(
        select(Tenant, func.coalesce(admin_counts.c.admin_count, 0))
        .outerjoin(admin_counts, admin_counts.c.tenant_id == Tenant.id)
        .order_by(Tenant.name)
    )).all()
    return [
        {
            "id": str(tenant.id),
            "name": tenant.name,
            "invite_code": tenant.join_code,
            "is_emergency_active": tenant.is_emergency_active,
            "admin_count": admin_count,
        }
        for tenant, admin_count in rows
    ]
