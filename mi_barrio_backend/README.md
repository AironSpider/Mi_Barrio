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

## Despliegue público para la demo (Neon + Render)

En [Neon](https://neon.com/), crea un proyecto PostgreSQL y copia desde
**Connect** la cadena de conexión (puedes usar el endpoint pooled). En Render,
crea un Blueprint desde este repositorio y pega esa cadena como `DATABASE_URL`
cuando el panel la solicite. Usa la cadena PostgreSQL con SSL; el backend la
adapta a `asyncpg`, incluyendo `sslmode=require` y
`channel_binding=require`. Render genera `MI_BARRIO_JWT_SECRET`; nunca copies
el `.env` local ni una URL con contraseña al repositorio.

El contexto de Docker apunta a `mi_barrio_backend`, el puerto usa el
`$PORT` que entrega Render y las migraciones corren al iniciar el contenedor.
El arranque **no** crea cuentas ni ejecuta el seed: `seed_demo.py` requiere
`SEED_DEMO_PASSWORD` y es idempotente, y el SUPER_ADMIN se crea una sola vez
con `python -m app.features.auth_barrio.platform_admin_bootstrap`. Para crear
esa cuenta en el Neon desplegado, ejecuta el bootstrap desde una terminal local
con `DATABASE_URL` apuntando temporalmente a Neon. No guardes esa URL en Git ni
la envíes por chat.

Verifica `https://TU-URL/health/live` para la vida de la API y
`https://TU-URL/health` para comprobar conectividad con Neon y que las
migraciones están al día.

### Mantener Render despierto (opcional)

En Cron-job.org crea un GET cada 10 minutos a
`https://TU-URL/health/live`. Ese endpoint y el health check de Docker no
consultan PostgreSQL: mantienen activa la API sin impedir que Neon ahorre
recursos. El primer acceso tras varios minutos puede tardar mientras Neon
reactiva su compute; los timeouts de la app permiten hasta 30 segundos.

Esto reduce la posibilidad de cold start de Render, pero no es una garantía de
disponibilidad: Render puede reiniciar/suspender servicios gratuitos y Neon
Free escala su compute a cero tras inactividad y tiene cuotas mensuales. Revisa
los límites vigentes de [Render Free](https://render.com/docs/free) y
[Neon Free](https://neon.com/pricing). El `/health` normal sí consulta la base,
así que no lo uses como keep-alive frecuente si quieres que Neon pueda dormir.

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
