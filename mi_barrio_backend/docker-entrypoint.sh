#!/bin/sh
# Arranque del contenedor: migraciones y luego la API.
set -e

if [ -z "$DATABASE_URL" ]; then
  echo "Falta DATABASE_URL (usa --env-file .env)." >&2
  exit 1
fi
if [ -z "$MI_BARRIO_JWT_SECRET" ]; then
  echo "Falta MI_BARRIO_JWT_SECRET (usa --env-file .env)." >&2
  exit 1
fi

# Dentro del contenedor "localhost" es el propio contenedor: si la base de
# datos está en la PC (PostgreSQL local), se usa host.docker.internal.
DATABASE_URL=$(printf '%s' "$DATABASE_URL" | sed -e 's/@localhost\([:/]\)/@host.docker.internal\1/' -e 's/@127\.0\.0\.1\([:/]\)/@host.docker.internal\1/')
export DATABASE_URL

python -m alembic upgrade head
# 1 proceso: el límite de intentos de login vive en memoria y debe ser uno solo.
# Render (y otros) indican el puerto en $PORT; en la PC se usa 8000.
# --proxy-headers: detrás del proxy de Render, la IP real del vecino (límite de intentos).
exec python -m uvicorn app.main:app --host 0.0.0.0 --port "${PORT:-8000}" \
  --proxy-headers --forwarded-allow-ips="*"
