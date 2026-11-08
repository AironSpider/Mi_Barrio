# Mi Barrio API (Sprint 12, Dev 1).
# Construir y levantar (desde mi_barrio_backend):
#   docker build -t mi-barrio-api . && docker run --rm -p 8000:8000 --env-file .env --add-host=host.docker.internal:host-gateway mi-barrio-api
# Al arrancar aplica `alembic upgrade head` y luego levanta uvicorn.
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY alembic.ini .
COPY alembic ./alembic
COPY app ./app
COPY docker-entrypoint.sh .
RUN sed -i 's/\r$//' docker-entrypoint.sh && chmod +x docker-entrypoint.sh \
    && useradd --create-home --uid 10001 api && chown -R api /app
USER api

EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s \
    CMD python -c "import os,urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:%s/health' % os.environ.get('PORT', '8000'), timeout=4).status == 200 else 1)"

ENTRYPOINT ["./docker-entrypoint.sh"]
