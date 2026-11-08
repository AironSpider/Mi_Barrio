"""Crea el PRIMER superadministrador (solo funciona una vez por base de datos).

Uso (desde mi_barrio_backend):
    DATABASE_URL='postgresql://...neon.tech/...' .venv/bin/python -m app.features.auth_barrio.platform_admin_bootstrap

Sin DATABASE_URL en el entorno usa la de .env (la base local). Antes de pedir
los datos muestra en qué servidor se va a crear la cuenta.
"""
import asyncio
import getpass
import re
import sys

from sqlalchemy import select
from sqlalchemy.engine import make_url

from app.core.auth_security import hash_password
from app.core.database import DATABASE_URL, async_session_factory, engine
from app.features.auth_barrio.models import PlatformAdmin, User


async def create_platform_admin() -> None:
    """Pide por consola nombre, correo y contraseña y crea el primer superadministrador. Solo funciona una vez: si ya existe uno, se detiene."""
    url = make_url(DATABASE_URL)
    print(f"Base de datos: {url.host}/{url.database}")
    full_name = input("Nombre del superadministrador: ").strip()
    email = input("Correo del superadministrador: ").strip().lower()
    password = getpass.getpass("Contraseña (mínimo 8 caracteres): ")
    confirmation = getpass.getpass("Repite la contraseña: ")

    if len(full_name) < 2:
        raise ValueError("El nombre debe tener al menos 2 caracteres")
    if not re.fullmatch(r"[^@\s]+@[^@\s]+\.[^@\s]+", email):
        raise ValueError("Ingresa un correo válido")
    if len(password) < 8 or len(password) > 128:
        raise ValueError("La contraseña debe tener entre 8 y 128 caracteres")
    if password != confirmation:
        raise ValueError("Las contraseñas no coinciden")

    async with async_session_factory() as db:
        existing_platform_admin = await db.scalar(
            select(PlatformAdmin.id).limit(1)
        )
        if existing_platform_admin is not None:
            raise ValueError(
                "Ya existe un SUPER_ADMIN. El bootstrap inicial solo se ejecuta una vez."
            )
        email_in_users = await db.scalar(select(User.id).where(User.email == email))
        email_in_admins = await db.scalar(
            select(PlatformAdmin.id).where(PlatformAdmin.email == email)
        )
        if email_in_users is not None or email_in_admins is not None:
            raise ValueError("Ese correo ya tiene una cuenta")
        db.add(
            PlatformAdmin(
                full_name=full_name,
                email=email,
                password_hash=hash_password(password),
            )
        )
        await db.commit()
    print(f"SUPER_ADMIN creado: {email}")


async def _main() -> int:
    try:
        await create_platform_admin()
        return 0
    except ValueError as error:
        print(f"No se creó: {error}", file=sys.stderr)
        return 1
    finally:
        # Cierra las conexiones antes de que termine el event loop.
        await engine.dispose()


if __name__ == "__main__":
    sys.exit(asyncio.run(_main()))
