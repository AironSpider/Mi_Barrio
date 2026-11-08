from sqlalchemy.engine import make_url


def normalize_database_url(database_url: str) -> str:
    """Convert provider PostgreSQL URLs to SQLAlchemy's asyncpg URL format."""
    url = make_url(database_url)
    if url.drivername in {"postgres", "postgresql"}:
        url = url.set(drivername="postgresql+asyncpg")

    if url.drivername == "postgresql+asyncpg":
        query = dict(url.query)
        sslmode = query.pop("sslmode", None)
        query.pop("channel_binding", None)
        if sslmode is not None:
            query.setdefault("ssl", sslmode)
        url = url.set(query=query)

    return url.render_as_string(hide_password=False)
