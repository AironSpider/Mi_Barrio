import os
from dotenv import load_dotenv
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession
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
    pass

async def get_db_session() -> AsyncSession:
    async with async_session_factory() as session:
        yield session
