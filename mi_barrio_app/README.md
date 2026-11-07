# Mi Barrio

## Backend y autenticación

Antes de iniciar FastAPI, define una clave JWT estable de al menos 32 caracteres
y aplica las migraciones. No regeneres la clave en cada inicio ni la guardes en
el repositorio: cambiarla invalida los tokens emitidos anteriormente.

```bash
cd ../mi_barrio_backend
# Solo si todavía no tienes .env:
cp .env.example .env
# Edita .env: reemplaza las credenciales de DATABASE_URL.
openssl rand -hex 32
# Pega el resultado en MI_BARRIO_JWT_SECRET dentro de .env.
.venv/bin/alembic upgrade head
.venv/bin/python -m app.features.auth_barrio.platform_admin_bootstrap
.venv/bin/uvicorn app.main:app --reload --port 8000
```

El backend y Alembic leen `.env` al arrancar. Cada integrante del equipo crea
su propio `.env` local; se comparte el `.env.example`, nunca las contraseñas ni
la clave JWT. La base de datos también impone unicidad al código de invitación;
si ocurre una colisión al generar uno, el backend lo regenera antes de guardar
el barrio.

La clave JWT que se compartió anteriormente debe considerarse comprometida:
cada desarrollador debe generar una nueva con `openssl rand -hex 32`, guardarla
solo en su `.env` local y reiniciar FastAPI. Esto invalida todos los tokens
emitidos con la clave anterior.

El comando de bootstrap solicita nombre, correo y contraseña sin almacenarlos en
el código. Ejecútalo manualmente una sola vez para crear el SUPER_ADMIN inicial.
Desde su pantalla de administración se crean barrios y cuentas ADMIN_BARRIO; el
sistema genera el código que el administrador comparte con los vecinos y
comerciantes. El barrio de demostración existente mantiene el código
`BARRIO-01`; el SUPER_ADMIN también puede asignarle una cuenta administradora
ingresando ese código.

La sesión y el token se conservan en el dispositivo. Al cerrar sesión se detiene
la sincronización autenticada. SQLite en el teléfono guarda los datos offline;
la creación de barrios, cuentas y códigos vive en PostgreSQL.

## Ejecutar Flutter

```bash
flutter pub get
flutter run
```

En Linux/Windows el backend local usa `http://localhost:8000`. Para Android,
define la URL de la computadora accesible desde el teléfono, por ejemplo:

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000
```

`API_BASE_URL` es una variable de compilación de Flutter, no se carga desde el
`.env` del backend.

## Pruebas

```bash
flutter analyze
flutter test
```

Las pruebas de `test/e2e` requieren el backend levantado, las migraciones
actualizadas, una cuenta SUPER_ADMIN y estas variables para aprovisionar un
barrio de prueba aislado (no se modifica `BARRIO-01`):

```bash
flutter test test/e2e --dart-define=API_BASE_URL=http://localhost:8000 \
  --dart-define=E2E_SUPER_ADMIN_EMAIL=admin@example.test \
  --dart-define=E2E_SUPER_ADMIN_PASSWORD='tu-clave-local'
```

La cuenta debe existir en la instancia local. Si el backend, las migraciones o
las credenciales no están disponibles, la integración se omite.
