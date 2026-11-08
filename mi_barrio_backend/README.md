# Mi Barrio API (backend)

FastAPI + PostgreSQL, multi-barrio y offline-first.

## Opción rápida: Docker (un solo comando)

Requisitos: Docker Desktop y PostgreSQL encendido. Copia `.env.example` a `.env`
y llena `DATABASE_URL` y `MI_BARRIO_JWT_SECRET` (**sin comillas**: Docker no las quita).

Desde `mi_barrio_backend`:

```
docker build -t mi-barrio-api . && docker run --rm -p 8000:8000 --env-file .env --add-host=host.docker.internal:host-gateway mi-barrio-api
```

- Al arrancar aplica las migraciones (`alembic upgrade head`) y levanta la API en el puerto 8000.
- Si `DATABASE_URL` apunta a `localhost`, el contenedor usa la PostgreSQL de tu PC (`host.docker.internal`).
- El `.env` **no** entra en la imagen (`.dockerignore`); se pasa solo al ejecutar.

Comprobar: abre <http://localhost:8000/health> → `"migrations_up_to_date": true`.
Documentación interactiva: <http://localhost:8000/docs>.

## Sin Docker (desarrollo)

```
python -m venv venv
venv\Scripts\python.exe -m pip install -r requirements.txt
venv\Scripts\python.exe -m alembic upgrade head
venv\Scripts\python.exe -m uvicorn app.main:app --reload
```

## Datos de demo (barrio BARRIO-01)

```
$env:SEED_DEMO_PASSWORD = "tu-clave-de-demo"
venv\Scripts\python.exe scripts\seed_demo.py
```

Se puede correr varias veces (no duplica). La clave nunca se escribe en el repo.

## Pruebas (con la API levantada)

```
venv\Scripts\python.exe scripts\smoke_test_api.py
venv\Scripts\python.exe scripts\test_sprint6_backend.py
venv\Scripts\python.exe scripts\load_test_sync.py
```

`load_test_sync.py` simula 20 vecinos sincronizando a la vez (push + pull) en un
barrio de prueba propio; nunca toca BARRIO-01. Opciones: `--vecinos 20 --rondas 3`.
