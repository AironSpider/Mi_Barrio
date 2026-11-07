import uuid
import secrets

from fastapi import APIRouter, Depends, HTTPException, Request, status
from starlette.concurrency import run_in_threadpool
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.exc import IntegrityError

from app.core import rate_limit
from app.core.auth_security import create_access_token, hash_password, verify_password
from app.core.database import get_db_session
from app.core.tenant_middleware import require_role
from app.features.auth_barrio.models import PlatformAdmin, Tenant, User
from app.features.auth_barrio.schemas import (
    AuthResponse,
    AuthUserResponse,
    LoginRequest,
    NeighborhoodAdminCreate,
    NeighborhoodAdminCreated,
    PlatformAdminResponse,
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


def _auth_response(
    user: User,
    tenant: Tenant,
    access_token: str | None = None,
) -> AuthResponse:
    return AuthResponse(
        access_token=access_token
        or create_access_token(
            user_id=user.id,
            tenant_id=user.tenant_id,
            role=user.role,
        ),
        user=AuthUserResponse(
            id=user.id,
            tenant_id=user.tenant_id,
            full_name=user.full_name,
            email=user.email,
            role=user.role,
            is_approved=user.is_approved,
            tenant=TenantResponse.model_validate(tenant),
        ),
    )


@router.post("/register", response_model=AuthResponse, status_code=status.HTTP_201_CREATED)
async def register(payload: RegisterRequest, db: AsyncSession = Depends(get_db_session)):
    email = payload.email.strip().lower()
    join_code = payload.join_code.strip().upper()
    tenant = await db.scalar(select(Tenant).where(Tenant.join_code == join_code))
    if tenant is None:
        raise HTTPException(status_code=404, detail="No encontramos un barrio con ese código")

    existing = await db.scalar(select(User.id).where(User.email == email))
    platform_admin = await db.scalar(
        select(PlatformAdmin.id).where(PlatformAdmin.email == email)
    )
    if existing is not None or platform_admin is not None:
        raise HTTPException(status_code=409, detail="Ya existe una cuenta con ese correo")

    user = User(
        id=uuid.uuid4(),
        tenant_id=tenant.id,
        full_name=payload.full_name.strip(),
        email=email,
        password_hash=await _hash(payload.password),
        role=payload.role,
        is_approved=payload.role != "COMERCIANTE",
        phone="",
        home_lat=tenant.center_lat,
        home_lng=tenant.center_lng,
        tutorial_completed=False,
    )
    db.add(user)
    access_token = create_access_token(
        user_id=user.id,
        tenant_id=user.tenant_id,
        role=user.role,
    )
    try:
        await db.commit()
    except IntegrityError as exc:
        await db.rollback()
        raise HTTPException(
            status_code=409,
            detail="Ya existe una cuenta con ese correo",
        ) from exc
    await db.refresh(user)
    return _auth_response(user, tenant, access_token)


@router.post("/login", response_model=AuthResponse)
async def login(
    payload: LoginRequest,
    request: Request,
    db: AsyncSession = Depends(get_db_session),
):
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
            user=PlatformAdminResponse(
                id=platform_admin.id,
                full_name=platform_admin.full_name,
                email=platform_admin.email,
            ),
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
    return _auth_response(user, tenant)


@router.get("/me", response_model=AuthUserResponse)
async def current_user(
    request: Request,
    db: AsyncSession = Depends(get_db_session),
):
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
        return PlatformAdminResponse(
            id=admin.id,
            full_name=admin.full_name,
            email=admin.email,
        )
    user = await db.scalar(
        select(User).where(User.id == user_id, User.is_deleted.is_(False))
    )
    if user is None or user.tenant_id != uuid.UUID(claims["tenant_id"]):
        raise HTTPException(status_code=401, detail="La sesión ya no es válida")
    tenant = await db.get(Tenant, user.tenant_id)
    if tenant is None:
        raise HTTPException(status_code=403, detail="El barrio de la cuenta no está disponible")
    return AuthUserResponse(
        id=user.id,
        tenant_id=user.tenant_id,
        full_name=user.full_name,
        email=user.email,
        role=user.role,
        is_approved=user.is_approved,
        tenant=TenantResponse.model_validate(tenant),
    )


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
    super_admin = await db.scalar(
        select(PlatformAdmin).where(
            PlatformAdmin.id == uuid.UUID(principal["sub"]),
            PlatformAdmin.is_active.is_(True),
        )
    )
    if super_admin is None:
        raise HTTPException(status_code=401, detail="La sesión ya no es válida")

    email = payload.admin_email.strip().lower()
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
        if payload.center_lat is None or payload.center_lng is None:
            raise HTTPException(
                status_code=422,
                detail="Se requieren coordenadas para crear un barrio nuevo",
            )
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
        administrator=AuthUserResponse(
            id=neighborhood_admin.id,
            tenant_id=neighborhood_admin.tenant_id,
            full_name=neighborhood_admin.full_name,
            email=neighborhood_admin.email,
            role="ADMIN_BARRIO",
            tenant=TenantResponse.model_validate(tenant),
        ),
    )


@platform_router.get("/neighborhoods")
async def list_neighborhoods(
    principal: dict = Depends(require_role(["SUPER_ADMIN"])),
    db: AsyncSession = Depends(get_db_session),
):
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
