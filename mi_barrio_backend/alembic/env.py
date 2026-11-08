import asyncio
from logging.config import fileConfig

from sqlalchemy import pool
from sqlalchemy.engine import Connection
from sqlalchemy.ext.asyncio import async_engine_from_config
from dotenv import load_dotenv

from alembic import context

# IMPORTANTE: Importar Base y TODOS los modelos para que Alembic los detecte
# (se importan por su efecto: registran las tablas en Base.metadata).
from app.core.database import Base
import app.features.auth_barrio.models  # noqa: F401
import app.features.chat.models  # noqa: F401
import app.features.emergency_support.models  # noqa: F401
import app.features.moderation.models  # noqa: F401
import app.features.proximity_services.models  # noqa: F401
import app.features.solidarity_network.models  # noqa: F401

config = context.config
load_dotenv()

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

target_metadata = Base.metadata

# Misma URL que la API (app.core.database), ya convertida a postgresql+asyncpg://.
# Render entrega "postgresql://…": sin convertirla, las migraciones fallan al
# arrancar el contenedor. El "%" se duplica porque alembic.ini usa configparser.
from app.core.database import DATABASE_URL  # noqa: E402

config.set_main_option("sqlalchemy.url", DATABASE_URL.replace("%", "%%"))

def run_migrations_offline() -> None:
    url = config.get_main_option("sqlalchemy.url")
    context.configure(
        url=url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )
    with context.begin_transaction():
        context.run_migrations()

def do_run_migrations(connection: Connection) -> None:
    context.configure(connection=connection, target_metadata=target_metadata)
    with context.begin_transaction():
        context.run_migrations()

async def run_async_migrations() -> None:
    connectable = async_engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )
    async with connectable.connect() as connection:
        await connection.run_sync(do_run_migrations)
    await connectable.dispose()

def run_migrations_online() -> None:
    asyncio.run(run_async_migrations())

if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()