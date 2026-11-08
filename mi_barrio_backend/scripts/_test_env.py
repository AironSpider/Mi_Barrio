"""Ayudas comunes para los scripts de prueba contra el backend levantado.

`isolated_neighborhood()` crea un barrio NUEVO solo para la prueba, con su
ADMIN_BARRIO, directamente en la base de datos (usa la misma DATABASE_URL que el
servidor, desde el entorno o mi_barrio_backend/.env). Así las pruebas nunca
ensucian el barrio demo BARRIO-01. Las contraseñas son aleatorias y no se imprimen.
"""
import asyncio
import json
import secrets
import sys
import urllib.error
import urllib.request
import uuid
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parent.parent
if str(BACKEND_DIR) not in sys.path:
    sys.path.insert(0, str(BACKEND_DIR))


def http(base: str, method: str, path: str, body=None, *, tenant: str | None = None,
         token: str | None = None, timeout: int = 30):
    headers = {"Content-Type": "application/json"}
    if tenant:
        headers["X-Tenant-ID"] = tenant
    if token:
        headers["Authorization"] = "Bearer " + token
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(base + path, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw = r.read().decode()
            return r.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw)
        except ValueError:
            return e.code, raw


async def _create_neighborhood(name: str) -> dict:
    from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine
    from sqlalchemy.pool import NullPool

    from app.core.auth_security import hash_password
    from app.core.database import DATABASE_URL
    from app.features.auth_barrio.models import Tenant, User

    # Motor propio por llamada (cada asyncio.run usa un event loop nuevo).
    engine = create_async_engine(DATABASE_URL, poolclass=NullPool)
    async_session_factory = async_sessionmaker(engine, expire_on_commit=False)

    tenant_id = uuid.uuid4()
    join_code = "TEST-" + secrets.token_hex(4).upper()
    admin_email = f"admin.{secrets.token_hex(4)}@pruebas.test"
    admin_password = secrets.token_urlsafe(16)
    async with async_session_factory() as db:
        db.add(Tenant(id=tenant_id, name=name, join_code=join_code,
                      center_lat=-5.1945, center_lng=-80.6328, is_emergency_active=False))
        await db.flush()
        db.add(User(id=uuid.uuid4(), tenant_id=tenant_id, full_name="Admin de pruebas",
                    email=admin_email, password_hash=hash_password(admin_password),
                    role="ADMIN_BARRIO", phone="", home_lat=-5.1945, home_lng=-80.6328,
                    tutorial_completed=True))
        await db.commit()
    await engine.dispose()
    return {"tenant_id": str(tenant_id), "join_code": join_code,
            "admin_email": admin_email, "admin_password": admin_password}


def isolated_neighborhood(base: str, name: str = "Pruebas automáticas") -> dict:
    """Barrio nuevo + token de su ADMIN_BARRIO."""
    hood = asyncio.run(_create_neighborhood(name))
    s, r = http(base, "POST", "/api/v1/auth/login",
                {"email": hood["admin_email"], "password": hood["admin_password"]})
    if s != 200:
        raise RuntimeError(f"No se pudo iniciar sesión como admin de prueba: {s} {r}")
    hood["admin_token"] = r["access_token"]
    return hood


def register(base: str, join_code: str, role: str, name: str = "Vecino de prueba") -> dict:
    """Crea una cuenta VECINO o COMERCIANTE en el barrio y devuelve su token e id."""
    email = f"{role.lower()}.{secrets.token_hex(4)}@pruebas.test"
    password = secrets.token_urlsafe(14)
    s, r = http(base, "POST", "/api/v1/auth/register", {
        "full_name": name, "email": email, "password": password,
        "role": role, "join_code": join_code, "accept_terms": True})
    if s != 201:
        raise RuntimeError(f"No se pudo registrar {role}: {s} {r}")
    return {
        "token": r["access_token"],
        "id": r["user"]["id"],
        "email": email,
        "password": password,
        "is_approved": r["user"].get("is_approved", True),
    }


async def _platform_admin(action: str, email: str, password: str = "") -> None:
    from sqlalchemy import delete
    from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine
    from sqlalchemy.pool import NullPool

    from app.core.auth_security import hash_password
    from app.core.database import DATABASE_URL
    from app.features.auth_barrio.models import PlatformAdmin

    engine = create_async_engine(DATABASE_URL, poolclass=NullPool)
    async with async_sessionmaker(engine, expire_on_commit=False)() as db:
        if action == "create":
            db.add(PlatformAdmin(full_name="Superadmin de pruebas", email=email,
                                 password_hash=hash_password(password)))
        else:
            await db.execute(delete(PlatformAdmin).where(PlatformAdmin.email == email))
        await db.commit()
    await engine.dispose()


def temporary_platform_admin() -> dict:
    """SUPER_ADMIN solo para la prueba. Llamar a `remove_platform_admin` al final:
    si quedara en la base, el bootstrap real (`platform_admin_bootstrap`) se negaría
    a crear el primer superadministrador."""
    email = f"superadmin.{secrets.token_hex(4)}@pruebas.test"
    password = secrets.token_urlsafe(16)
    asyncio.run(_platform_admin("create", email, password))
    return {"email": email, "password": password}


def remove_platform_admin(email: str) -> None:
    asyncio.run(_platform_admin("delete", email))
