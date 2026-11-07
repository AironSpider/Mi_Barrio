import uuid
import secrets

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.exc import IntegrityError

from app.core.auth_security import create_access_token, hash_password, verify_password
from app.core.database import get_db_session
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
        password_hash=hash_password(payload.password),
        role=payload.role,
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
async def login(payload: LoginRequest, db: AsyncSession = Depends(get_db_session)):
    email = payload.email.strip().lower()
    platform_admin = await db.scalar(
        select(PlatformAdmin).where(
            PlatformAdmin.email == email,
            PlatformAdmin.is_active.is_(True),
        )
    )
    if platform_admin is not None:
        if not verify_password(payload.password, platform_admin.password_hash):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Correo o contraseña incorrectos",
                headers={"WWW-Authenticate": "Bearer"},
            )
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
    if user is None or not verify_password(payload.password, user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Correo o contraseña incorrectos",
            headers={"WWW-Authenticate": "Bearer"},
        )
    tenant = await db.get(Tenant, user.tenant_id)
    if tenant is None:
        raise HTTPException(status_code=403, detail="La cuenta ya no pertenece a un barrio activo")
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
        tenant=TenantResponse.model_validate(tenant),
    )


platform_router = APIRouter(prefix="/api/v1/platform", tags=["Platform administration"])


def _new_join_code() -> str:
    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    return "MB-" + "".join(secrets.choice(alphabet) for _ in range(10))


@platform_router.post(
    "/neighborhoods",
    response_model=NeighborhoodAdminCreated,
    status_code=status.HTTP_201_CREATED,
)
async def create_neighborhood(
    payload: NeighborhoodAdminCreate,
    request: Request,
    db: AsyncSession = Depends(get_db_session),
):
    claims = getattr(request.state, "auth_claims", None)
    if claims is None or claims.get("role") != "SUPER_ADMIN":
        raise HTTPException(status_code=403, detail="Solo SUPER_ADMIN puede crear barrios")
    super_admin = await db.scalar(
        select(PlatformAdmin).where(
            PlatformAdmin.id == uuid.UUID(claims["sub"]),
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
        join_code = _new_join_code()
        while await db.scalar(select(Tenant.id).where(Tenant.join_code == join_code)):
            join_code = _new_join_code()
        tenant = Tenant(
            id=uuid.uuid4(),
            name=(payload.neighborhood_name or "").strip(),
            join_code=join_code,
            center_lat=payload.center_lat,
            center_lng=payload.center_lng,
            is_emergency_active=False,
        )
        db.add(tenant)

    neighborhood_admin = User(
        id=uuid.uuid4(),
        tenant_id=tenant.id,
        full_name=payload.admin_full_name.strip(),
        email=email,
        password_hash=hash_password(payload.admin_password),
        role="ADMIN_BARRIO",
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
