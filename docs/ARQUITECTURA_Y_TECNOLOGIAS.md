# Mi Barrio: arquitectura y tecnologías

**Titular:** NetSurex · **Equipo:** Root Crew Code · Hackathon UTP – El Comercio 2026
**Revisado contra el código:** 8 de noviembre de 2026

Este documento explica **cómo está construido** Mi Barrio y **qué tecnologías usa** cada parte. Para el detalle de cada archivo y función, ver [Documentación del código](DOCUMENTACION_DEL_CODIGO.md).

---

## 1. Vista general

Mi Barrio tiene **dos partes** que se comunican por internet:

| Parte | Qué es | Dónde vive |
| --- | --- | --- |
| **App** (`mi_barrio_app/`) | App móvil en **Flutter** (Android; también compila para iOS, web y Windows) | En el celular del vecino |
| **Backend** (`mi_barrio_backend/`) | API REST en **FastAPI** (Python) con base de datos **PostgreSQL** | En la nube: **Render** (servidor) + **Neon** (base de datos) |

```
 ┌───────────────────────── CELULAR ─────────────────────────┐        ┌──────────────────── NUBE ─────────────────────┐
 │                                                            │        │                                                │
 │  Pantallas (Flutter + Riverpod)                            │        │  Render (Docker, Python 3.12)                  │
 │      │  guardan primero en el celular                      │        │   FastAPI + Uvicorn                            │
 │      ▼                                                     │ HTTPS  │    ├─ TenantMiddleware (token + barrio)        │
 │  SQLite local  ──►  cola sync_outbox                       │ ─────► │    ├─ /api/v1/sync/push  (subir cambios)       │
 │      ▲                    │                                │ ◄───── │    ├─ /api/v1/sync/pull  (bajar novedades)     │
 │      │            SyncCoordinator / SyncWorker             │        │    ├─ REST: cuentas, servicios, apoyo, SOS…    │
 │      └────────── guarda lo que llega del pull              │  WSS   │    └─ WebSocket /api/v1/ws/chat (chat en vivo) │
 │                                                            │ ◄────► │            │                                   │
 │  Sesión (SharedPreferences) · GPS · Cámara                 │        │            ▼ SQLAlchemy async + asyncpg        │
 └────────────────────────────────────────────────────────────┘        │  Neon (PostgreSQL) · migraciones Alembic       │
                                                                       └────────────────────────────────────────────────┘
        Servicios externos:  Google (inicio de sesión) · Brevo / Gmail (correos) · OpenStreetMap (mapas)
```

---

## 2. Estilos de arquitectura que usa

| Patrón | Dónde | Qué significa en Mi Barrio |
| --- | --- | --- |
| **Cliente–servidor (REST)** | Todo | La app pide y envía datos al servidor por HTTP con JSON. |
| **Offline-first** | App + sync | Todo se guarda **primero en el celular** (SQLite) y se sincroniza después. La app funciona sin internet. |
| **Outbox + push/pull** | `sync_outbox`, `/sync/push`, `/sync/pull` | Los cambios hechos sin red esperan en una cola (*outbox*). Con red se suben en lote (push) y se bajan las novedades del barrio desde la última vez (pull, *delta*). |
| **Last-Write-Wins (LWW)** | Backend sync | Si dos celulares editan lo mismo, gana el cambio con `updated_at` más reciente. |
| **Borrado lógico** | Todas las tablas por barrio | No se borra la fila: se marca `is_deleted = true`, así el pull avisa a los otros celulares que la quiten. |
| **Multi-tenant (por barrio)** | Backend | Cada barrio es un *tenant*. Cada fila tiene `tenant_id`, y cada petición lleva el token y `X-Tenant-ID`: nadie ve datos de otro barrio. |
| **Arquitectura por funcionalidades** (*feature-first*) | App y backend | El código se organiza por funcionalidad (cuentas, servicios, apoyo, emergencia, chat…), no por tipo de archivo. |
| **Capas limpias** (*Clean Architecture* ligera) | App: `auth_barrio` y otras | `data` (datasources y modelos) → `domain` (entidades y contratos) → `presentation` (pantallas y providers). |
| **Repositorio + inyección por Provider** | App | Las pantallas usan interfaces (p. ej. `AuthRepository`) y en las pruebas se reemplazan por falsas. |
| **Middleware de seguridad** | Backend | `TenantMiddleware` revisa token, barrio y rutas públicas antes de cada endpoint. |
| **Tiempo real con WebSocket** | Chat | Los mensajes llegan al instante si el otro vecino está conectado. |

---

## 3. Tecnologías de la app (Flutter)

### 3.1 Base

| Tecnología | Versión | Para qué |
| --- | --- | --- |
| **Flutter** | 3.47 (canal estable) | Framework de la interfaz (una base de código para Android, iOS, web y Windows) |
| **Dart** | SDK ^3.13 | Lenguaje de la app |
| **Material 3** | incluido en Flutter | Componentes visuales. Tema propio de día y de emergencia, áreas táctiles de 48 px y textos grandes |
| **Android** | minSdk de Flutter (5.0+) | Plataforma principal (APK firmada con `upload-keystore.jks`) |

### 3.2 Paquetes (pubspec.yaml)

| Paquete | Versión | Para qué se usa |
| --- | --- | --- |
| `flutter_riverpod` | ^2.6.1 | Estado de la app (sesión, emergencia) con `StateNotifier` y providers |
| `sqflite` | ^2.3.3 | Base de datos **SQLite** en el celular (modo offline) |
| `sqflite_common_ffi` | ^2.4.5 | SQLite en escritorio y en las pruebas |
| `path` | ^1.9.0 | Rutas del archivo de la base local |
| `shared_preferences` | ^2.3.2 | Guardar la sesión (token) y preferencias |
| `http` | ^1.2.2 | Llamadas REST al backend |
| `web_socket_channel` | ^3.0.3 | Chat en tiempo real (WebSocket) |
| `connectivity_plus` | ^6.1.0 | Saber si hay red (Wi-Fi o datos) |
| `geolocator` | ^14.0.2 | GPS: ubicación para servicios cercanos y pedidos de ayuda |
| `flutter_map` | ^8.3.2 | Mapa con imágenes de **OpenStreetMap** |
| `latlong2` | ^0.10.1 | Coordenadas para el mapa |
| `image_picker` | ^1.2.4 | Fotos con cámara o galería (se achican a 800 px antes de subir) |
| `google_sign_in` | ^7.2.0 | "Continuar con Google" (ID token) |
| `flutter_svg` | ^2.3.2 | Logo oficial de Google en el botón |
| `url_launcher` | ^6.3.3 | Abrir llamadas, WhatsApp, mapas y enlaces |
| `share_plus` | ^13.3.1 | Compartir el código para invitar vecinos al barrio |
| `uuid` | ^4.5.1 | IDs creados en el celular (sirven sin internet) |
| `font_awesome_flutter` | ^11.0.0 | Íconos (WhatsApp, etc.) |
| `cupertino_icons` | ^1.0.8 | Íconos de iOS |
| `flutter_lints` (dev) | ^6.0.0 | Reglas de calidad del código (`flutter analyze`) |
| `flutter_launcher_icons` (dev) | ^0.14.4 | Generar el ícono de la app para todas las plataformas |

### 3.3 Estructura de la app

```
mi_barrio_app/lib/
├── main.dart                  Arranque: tema, sincronización y pantalla según la sesión (AuthGate)
├── core/                      Lo que usan todas las funcionalidades
│   ├── auth/                  Sesión guardada (token)
│   ├── barrio_context/        Barrio actual y Modo Emergencia
│   ├── database_sqlite/       SQLite: tablas, validaciones, cola outbox, historial
│   ├── location/              GPS
│   ├── moderation/            Filtro de groserías (misma lista que el servidor)
│   ├── network/               Cliente HTTP (X-Tenant-ID + token) y monitor de red
│   ├── realtime/              WebSocket del chat
│   ├── sync_manager/          SyncCoordinator (cuándo) y SyncWorker (push/pull)
│   └── ui_kit/                Tema, barra inferior, mapa, fotos, estrellas, etiquetas de sync…
├── features/                  Una carpeta por funcionalidad
│   ├── auth_barrio/           Login, registro, Google, código al correo, administradores
│   ├── proximity_services/    Servicios del barrio (Necesito / Ofrezco), reseñas
│   ├── solidarity_network/    Muro de apoyo (favores), comentarios, calificaciones
│   ├── emergency_support/     Modo emergencia: pedir ayuda, mapa, grupos de apoyo
│   ├── chat/                  Conversaciones entre vecinos
│   ├── moderation/            Reportes y cuentas suspendidas
│   ├── profile_me/            Pestaña "Tú": perfil, historial, borrar cuenta
│   ├── legal/                 Términos, privacidad y manual dentro de la app
│   └── onboarding_tutorial/   Tutorial de bienvenida
└── shared/                    Ayudas comunes (contacto, ranking de emergencia…)
```

### 3.4 Base de datos local (SQLite, versión de esquema 11)

| Tabla | Para qué |
| --- | --- |
| `solidarity_posts`, `post_photos`, `post_photo_list` | Favores del muro y sus fotos |
| `local_services`, `service_photos`, `neighbor_endorsements` | Servicios, sus fotos y reseñas |
| `vulnerable_reports`, `support_groups` | Pedidos de ayuda (SOS) y grupos de apoyo |
| `content_reports` | Reportes hechos por el vecino |
| `users` | Perfil propio y perfiles públicos del barrio |
| `sync_outbox` | **Cola de cambios pendientes de subir** |
| `sync_state` | Último momento sincronizado (cursor del pull) |
| `app_settings` | Preferencias locales |

---

## 4. Tecnologías del backend (FastAPI)

### 4.1 Base

| Tecnología | Versión | Para qué |
| --- | --- | --- |
| **Python** | 3.12 (en Docker) | Lenguaje del servidor |
| **FastAPI** | ≥ 0.110 | Framework de la API REST y WebSocket; genera Swagger en `/docs` |
| **Uvicorn** (`[standard]`) | ≥ 0.28 | Servidor ASGI que corre FastAPI |
| **Pydantic** | ≥ 2.6 | Validación de datos de entrada y salida (esquemas) |
| **SQLAlchemy** (async) | ≥ 2.0.28 | ORM: modelos de tablas y consultas |
| **asyncpg** | ≥ 0.29 | Driver asíncrono de PostgreSQL |
| **greenlet** | ≥ 3.0.3 | Requisito de SQLAlchemy async |
| **Alembic** | ≥ 1.13 | Migraciones de la base de datos (20 versiones) |
| **python-dotenv** | ≥ 1.0.1 | Leer `.env` en desarrollo |
| **PostgreSQL** | Neon (nube) / local | Base de datos principal |

Todo lo demás está hecho **con la biblioteca estándar de Python**, sin dependencias extra:

| Pieza | Con qué |
| --- | --- |
| Contraseñas | `hashlib.pbkdf2_hmac` (PBKDF2-SHA256 con sal) |
| Tokens de sesión | JWT HS256 propio con `hmac` + `hashlib` (24 h) |
| Códigos de correo | HMAC (se guarda la huella, nunca el código) |
| Envío de correos | `urllib` → API HTTPS de **Brevo**; o `smtplib` → Gmail |
| Validar Google | `urllib` → endpoint **tokeninfo** de Google |
| Límite de intentos | Contadores en memoria con `threading.Lock` |

### 4.2 Estructura del backend

```
mi_barrio_backend/
├── app/
│   ├── main.py                 Crea la API: middlewares, routers, /health y errores
│   ├── core/                   Seguridad y servicios comunes
│   │   ├── tenant_middleware.py   Token + X-Tenant-ID + roles
│   │   ├── auth_security.py       PBKDF2 y JWT
│   │   ├── database.py            Motor async y sesión por petición
│   │   ├── email_sender.py        Brevo / SMTP
│   │   ├── email_validation.py    Dominios que existen
│   │   ├── google_auth.py         Validar ID token de Google
│   │   ├── content_filter.py      Censura de groserías y odio
│   │   ├── rate_limit.py          Límite de intentos de login y códigos
│   │   ├── realtime.py            Conexiones WebSocket del chat
│   │   ├── log_redaction.py       Quita tokens de los logs
│   │   └── exceptions.py          Formato común de errores
│   ├── features/               Un módulo por funcionalidad (models, schemas, router, service)
│   │   ├── auth_barrio/           Cuentas, barrios, perfil, Google, códigos, borrar cuenta
│   │   ├── proximity_services/    Servicios y reseñas
│   │   ├── solidarity_network/    Favores, comentarios, calificaciones
│   │   ├── emergency_support/     SOS y grupos de apoyo
│   │   ├── chat/                  Mensajes y WebSocket
│   │   ├── moderation/            Reportes y suspensión
│   │   └── sync_engine/           Push y pull offline
│   └── shared/                 Columnas comunes (BarrioBaseMixin) y valores del contrato
├── alembic/versions/           Migraciones
├── scripts/                    Pruebas contra la API levantada, carga y datos demo
├── tests/                      Pruebas unitarias
├── Dockerfile · docker-entrypoint.sh   Imagen y arranque (aplica migraciones)
└── requirements.txt
```

Cada funcionalidad sigue el mismo patrón: **`models.py`** (tablas) → **`schemas.py`** (Pydantic) → **`router.py`** (endpoints) → **`service.py`** (lógica compartida).

### 4.3 Base de datos del servidor (PostgreSQL)

| Tabla | Para qué |
| --- | --- |
| `tenants` | Barrios: nombre, código para unirse, centro del mapa, Modo Emergencia |
| `users` | Cuentas: vecino, comerciante o administrador del barrio; perfil; contraseña o Google; suspensión |
| `platform_admins` | Superadministradores de la plataforma |
| `auth_codes` | Códigos de 6 números (verificar correo, recuperar contraseña) |
| `local_services`, `neighbor_endorsements` | Servicios y reseñas |
| `solidarity_posts`, `post_comments`, `favor_reviews` | Favores, comentarios y calificaciones |
| `vulnerable_reports`, `support_groups` | Emergencia |
| `chat_messages` | Chat |
| `content_reports` | Reportes de moderación |

Las tablas por barrio heredan **`BarrioBaseMixin`**: `id` (UUID), `tenant_id`, `is_deleted`, `created_at`, `updated_at` y `server_updated_at` (el cursor del pull).

---

## 5. Cómo funcionan los flujos principales

### 5.1 Sincronización offline-first

```
 Vecino publica ──► SQLite (sync_status = PENDING) ──► sync_outbox
                                                         │
          SyncCoordinator: al abrir la app, al volver internet y tras publicar
                                                         ▼
          PUSH  POST /api/v1/sync/push   (lote de hasta 200 cambios)
                 servidor valida, aplica LWW, censura al guardar y devuelve los rechazados
                                                         ▼
          PULL  GET /api/v1/sync/pull?since=<cursor>
                 servidor devuelve lo cambiado en el barrio desde el cursor (incluye borrados)
                                                         ▼
          SQLite se actualiza · sync_status = SYNCED · reintentos 2 → 4 → 8 → 16 s si falla
```

### 5.2 Cuentas e inicio de sesión

```
 Correo + contraseña ─► POST /auth/register ─► código al correo (Brevo) ─► POST /auth/email/verify
 Google ─► google_sign_in (ID token) ─► POST /auth/google ─► el servidor valida con Google (tokeninfo)
                                         └─ cuenta nueva sin código de barrio → 428 → la app lo pide
 Olvidé mi contraseña ─► POST /auth/password/forgot ─► código ─► POST /auth/password/reset
 Toda sesión ─► JWT (24 h) guardado en el celular ─► cada petición: Authorization + X-Tenant-ID
```

### 5.3 Seguridad por capas

| Capa | Cómo |
| --- | --- |
| Transporte | Todo por **HTTPS** y **WSS** |
| Identidad | JWT firmado (HS256, secreto `MI_BARRIO_JWT_SECRET`, 24 h) |
| Barrio | `TenantMiddleware`: el `X-Tenant-ID` debe ser el mismo barrio del token |
| Roles | `require_role(...)`: vecino, comerciante, admin del barrio, superadministrador |
| Contraseñas | PBKDF2-SHA256 con sal; comparación en tiempo constante |
| Fuerza bruta | 5 intentos por cuenta y 30 por IP cada 5 min (login y códigos) |
| Códigos | HMAC, 15 min, 5 intentos, 1 por minuto y 5 por hora; no revelan si el correo existe |
| Contenido | Filtro de groserías y odio (app + servidor); 3 reportes ocultan; suspensión por reportes |
| Datos inválidos | Pydantic rechaza (422) textos gigantes, coordenadas imposibles, tipos inventados |
| Logs | Tokens censurados (`token=***`); en producción los errores 500 no muestran detalles técnicos |
| Privacidad | Nombre corto público ("Rosa C."); correo nunca visible; borrar cuenta desde la app |

---

## 6. Infraestructura y despliegue

| Pieza | Servicio | Detalle |
| --- | --- | --- |
| Servidor | **Render** (plan gratis, región Ohio) | Despliegue con **Docker** desde `render.yaml`; salud en `/health/live`; se despliega solo con cada push a `main`. Duerme tras 15 min sin uso (tarda ~1 min en despertar). |
| Base de datos | **Neon** (PostgreSQL en la nube) | `DATABASE_URL`; migraciones Alembic al arrancar el contenedor |
| Correo | **Brevo** (API HTTPS, 300 correos/día gratis) | Render gratis bloquea SMTP; Gmail SMTP queda para desarrollo |
| Inicio con Google | **Google Cloud** (OAuth: cliente web + cliente Android con SHA-1) | `GOOGLE_CLIENT_IDS` en Render; `GOOGLE_SERVER_CLIENT_ID` en la app |
| Mapas | **OpenStreetMap** (tiles) | Sin clave; atribución © OpenStreetMap |
| Código | **GitHub** (`AironSpider/Mi_Barrio`) | Rama `main` |
| APK | Compilada con `flutter build apk --release`, firmada con `upload-keystore.jks` | La URL del servidor va en el código; el client ID de Google se pasa con `--dart-define=GOOGLE_SERVER_CLIENT_ID=…` |

### Variables de entorno del servidor

| Variable | Para qué |
| --- | --- |
| `DATABASE_URL` | Conexión a PostgreSQL (Neon) |
| `MI_BARRIO_JWT_SECRET` | Firma de los tokens (Render la genera) |
| `GOOGLE_CLIENT_IDS` | Client ID web de Google aceptado |
| `BREVO_API_KEY` | Envío de correos por Brevo |
| `SMTP_USER` / `SMTP_PASSWORD` | Remitente (y SMTP de Gmail en desarrollo) |
| `AUTH_DEBUG_CODES` | Solo pruebas locales: devuelve el código si no hay correo configurado |
| `API_DEBUG_ERRORS` | Mostrar el detalle de los errores 500 también en producción |

---

## 7. Calidad y pruebas

| Tipo | Herramienta | Cantidad |
| --- | --- | --- |
| Análisis estático | `flutter analyze` + `flutter_lints` | 0 problemas |
| Pruebas de la app | `flutter_test` (unitarias, widgets, accesibilidad, offline, e2e, red) | 367 pruebas en 44 archivos |
| Pruebas de la API | Scripts en `scripts/` contra el servidor levantado | smoke 115 · cuentas 39 · borrar cuenta 9 · sprint 6: 27 · sprint 9: 24 · grupos 20 · suspensión 13 · profundas 22 |
| Prueba de carga | `scripts/load_test_sync.py` | 20 vecinos sincronizando a la vez, p95 < 5 s, nada se pierde |
| Unitarias del backend | `unittest` en `tests/` | URL de base de datos y errores 500 |
| Documentación | Comentarios `///` y docstrings en todo el código | Ver [Documentación del código](DOCUMENTACION_DEL_CODIGO.md) |

---

## 8. Documentos relacionados

| Documento | Para qué |
| --- | --- |
| [Documentación del código](DOCUMENTACION_DEL_CODIGO.md) | Cada archivo, clase, función y ruta de la API |
| [Manual de usuario](manual_de_usuario.md) | Cómo usar la app |
| [Documentos legales](legal/README.md) | Términos, privacidad, normas, cookies, EULA y aviso legal |
| [Guía de cuentas reales](CUENTAS_REALES.md) | Configurar Google, correo y Render |
| [Plan del proyecto](PLAN_v4_mi_barrio.md) | Plan de sprints del equipo |
