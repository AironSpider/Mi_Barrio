"""Conexión asíncrona a PostgreSQL (SQLAlchemy) y sesión por petición."""
import os
from dotenv import load_dotenv
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession
from sqlalchemy import event
from sqlalchemy.orm import DeclarativeBase
from app.core.database_url import normalize_database_url

load_dotenv()

DATABASE_URL = os.getenv(
    "DATABASE_URL", 
    "postgresql+asyncpg://postgres:postgres@localhost:5432/mi_barrio_db"
)

DATABASE_URL = normalize_database_url(DATABASE_URL)

engine = create_async_engine(
    DATABASE_URL,
    echo=False,
    pool_size=5,
    max_overflow=5,
    pool_pre_ping=True,
    pool_recycle=240,
)

async_session_factory = async_sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False,
)

class Base(DeclarativeBase):
    """Clase base de todos los modelos SQLAlchemy (tablas) del proyecto."""
    pass


def _censor_text_fields(_mapper, _connection, target) -> None:
    """Antes de guardar CUALQUIER fila: groserías y odio → asteriscos.

    Así se cubren el sync, las rutas REST y el chat sin repetir código en cada
    una. Solo toca los campos de texto libre (título, descripción, mensaje…).
    """
    from app.core.content_filter import TEXT_FIELDS, censor, is_offensive

    for field in TEXT_FIELDS:
        value = getattr(target, field, None)
        if isinstance(value, str) and is_offensive(value):
            setattr(target, field, censor(value))


event.listen(Base, "before_insert", _censor_text_fields, propagate=True)
event.listen(Base, "before_update", _censor_text_fields, propagate=True)

async def get_db_session() -> AsyncSession:
    """Dependencia de FastAPI: abre una sesión de base de datos por petición y la cierra al terminar."""
    async with async_session_factory() as session:
        yield session
