# Mi Barrio: documentación del código

**Generado:** 08/11/2026 desde los comentarios del código con `scripts/generar_documentacion_codigo.py`.
**Titular:** NetSurex · **Equipo:** Root Crew Code · Hackathon UTP – El Comercio 2026

Este documento junta **todos los comentarios de documentación** del proyecto: los `///` de la app (Flutter/Dart) y los docstrings del backend (FastAPI/Python). Si cambias un comentario en el código, vuelve a correr el script y este documento se actualiza solo.

| | Archivos | Elementos documentados |
| --- | --- | --- |
| App (Flutter) | 117 | 511 |
| Backend (FastAPI) | 46 | 202 (de ellos 58 rutas de la API) |

## Índice

1. [Cómo está hecho Mi Barrio](#cómo-está-hecho-mi-barrio)
2. [Rutas de la API](#rutas-de-la-api)
3. [App (Flutter)](#app-flutter)
   - [Arranque de la app](#app-arranque-de-la-app)
   - [Núcleo (core): base de datos local, sincronización, red, sesión y diseño](#app-núcleo-core-base-de-datos-local-sincronización-red-sesión-y-diseño)
   - [Utilidades compartidas](#app-utilidades-compartidas)
   - [Cuentas: login, registro, Google, correo y administradores](#app-cuentas-login-registro-google-correo-y-administradores)
   - [Chat entre vecinos](#app-chat-entre-vecinos)
   - [Modo emergencia: pedir ayuda, mapa y grupos de apoyo](#app-modo-emergencia-pedir-ayuda-mapa-y-grupos-de-apoyo)
   - [Documentos legales dentro de la app](#app-documentos-legales-dentro-de-la-app)
   - [Moderación: reportes y cuentas suspendidas](#app-moderación-reportes-y-cuentas-suspendidas)
   - [Tutorial de bienvenida](#app-tutorial-de-bienvenida)
   - [Pestaña Tú: perfil, historial y cuenta](#app-pestaña-tú-perfil-historial-y-cuenta)
   - [Servicios del barrio](#app-servicios-del-barrio)
   - [Apoyo: muro de favores](#app-apoyo-muro-de-favores)
4. [Backend (FastAPI)](#backend-fastapi)
   - [Arranque de la API](#backend-arranque-de-la-api)
   - [Núcleo (core): seguridad, base de datos, correo, Google y errores](#backend-núcleo-core-seguridad-base-de-datos-correo-google-y-errores)
   - [Piezas compartidas](#backend-piezas-compartidas)
   - [Cuentas, barrios y perfil](#backend-cuentas-barrios-y-perfil)
   - [Chat entre vecinos](#backend-chat-entre-vecinos)
   - [Modo emergencia](#backend-modo-emergencia)
   - [Moderación](#backend-moderación)
   - [Servicios del barrio](#backend-servicios-del-barrio)
   - [Muro de apoyo](#backend-muro-de-apoyo)
   - [Sincronización offline-first](#backend-sincronización-offline-first)

---

## Cómo está hecho Mi Barrio

```
Celular (Flutter)                                 Servidor (Render)
┌──────────────────────────────┐                  ┌────────────────────────────┐
│ Pantallas (features/*)       │                  │ FastAPI (app/features/*)   │
│   ↓ guardan primero aquí     │   push / pull    │   TenantMiddleware:        │
│ SQLite local + cola outbox   │ ───────────────▶ │   token + X-Tenant-ID      │
│   ↑ SyncCoordinator          │ ◀─────────────── │ PostgreSQL (Neon)          │
│ Sesión (SharedPreferences)   │   HTTPS + JWT    │ Correo: Brevo / Gmail      │
└──────────────────────────────┘                  │ Google: tokeninfo          │
                                                  └────────────────────────────┘
```

- **Offline-first:** todo lo que hace el vecino se guarda primero en el celular (SQLite) y entra a una cola (`sync_outbox`). Cuando hay internet, `SyncCoordinator` sube la cola (**push**) y baja lo nuevo del barrio (**pull**). Los choques se resuelven con *gana el último* (LWW, por `updated_at`).
- **Por barrio (multi-tenant):** cada petición lleva el token de sesión y `X-Tenant-ID`; el servidor no deja leer ni escribir en otro barrio.
- **Cuentas:** correo + contraseña (PBKDF2) o Google; código de 6 números al correo para confirmar y para recuperar la contraseña; borrar la cuenta desde la app.
- **Roles:** vecino, comerciante, administrador del barrio y superadministrador de la plataforma.

---

## Rutas de la API

La misma información se ve en Swagger: `/docs` del servidor.

| Ruta | Qué hace |
| --- | --- |
| `POST /api/v1/auth/email/send-code` | Reenvía el código para confirmar el correo. Responde igual exista o no la cuenta (no revela correos). |
| `POST /api/v1/auth/email/verify` | Confirma el correo con el código de 6 números y devuelve la sesión. Limita los intentos por correo e IP. |
| `POST /api/v1/auth/google` | Entra con Google, o crea la cuenta la primera vez (428 si falta el código del barrio). |
| `POST /api/v1/auth/login` | Inicia sesión con correo y contraseña. Tras varios intentos fallidos pide esperar (429). |
| `GET /api/v1/auth/me` | Datos de la cuenta de la sesión actual (para restaurar la sesión al abrir la app). |
| `POST /api/v1/auth/password/forgot` | "¿Olvidaste tu contraseña?": envía un código al correo. Responde igual exista o no la cuenta. |
| `POST /api/v1/auth/password/reset` | Cambia la contraseña con el código del correo y deja la sesión iniciada. Limita los intentos. |
| `POST /api/v1/auth/password/set` | Quien entró con Google crea su contraseña (pide sesión iniciada). |
| `POST /api/v1/auth/register` | Crea la cuenta (vecino o comerciante) en el barrio del código, envía el código de verificación al correo y devuelve la sesión. |
| `DELETE /api/v1/auth/unverified-account` | "Volver para cambiar datos": borra la cuenta que nunca confirmó su correo, así el vecino puede registrarse de nuevo (con el mismo u otro correo). |
| `GET /api/v1/chat/inbox` | "Mis mensajes": todas mis conversaciones (como dueño o como vecino), la más reciente primero. |
| `GET /api/v1/chat/{kind}/{context_id}/conversations` | El dueño ve todas las conversaciones de su publicación; otro vecino, solo la suya. |
| `GET /api/v1/chat/{kind}/{context_id}/conversations/{neighbor_id}/messages` | Mensajes de una conversación (dueño de la publicación y un vecino). Solo la ven sus dos participantes. |
| `GET /api/v1/emergency/board` | Tablero de emergencia: pedidos de ayuda del barrio, los más recientes primero. Se puede filtrar por urgencia y estado. |
| `POST /api/v1/emergency/sos` | Crea un pedido de ayuda (SOS) a nombre del usuario de la sesión. |
| `GET /api/v1/emergency/support-groups` | Grupos de apoyo activos del barrio. Con `lat` y `lng`, del más cercano al más lejano (los que no tienen ubicación van al final); sin ellos, por nombre. |
| `POST /api/v1/emergency/support-groups` | Registra un grupo de apoyo. Solo el administrador del barrio (ADMIN_BARRIO). |
| `PATCH /api/v1/emergency/{report_id}/attend` | "Voy en camino": marca que el usuario va a ayudar. No se puede en el propio pedido ni en uno ya atendido. |
| `GET /api/v1/endorsements/{endorsement_id}/photo` | Foto de una reseña (se pide aparte para no cargar todas las fotos en la lista). |
| `GET /api/v1/moderation/reports` | Publicaciones reportadas del barrio (las que están en revisión primero). |
| `GET /api/v1/moderation/reports/count` | Admin del barrio: cuántas publicaciones esperan revisión. |
| `POST /api/v1/moderation/reports/{target_type}/{target_id}/{action}` | `restore` la vuelve a mostrar; `remove` la elimina. |
| `GET /api/v1/moderation/suspended` | Vecinos suspendidos por reportes, los más recientes primero. |
| `POST /api/v1/moderation/suspended/{user_id}/reactivate` | El vecino habló con el jefe del barrio: vuelve a usar la app. |
| `GET /api/v1/platform/neighborhoods` | Solo superadministrador: lista los barrios con su código y si tienen administrador. |
| `GET /api/v1/platform/reports` | Superadministrador: publicaciones reportadas de todos los barrios. |
| `GET /api/v1/platform/reports/count` | Superadministrador: cuántas publicaciones esperan revisión en total. |
| `POST /api/v1/platform/reports/{target_type}/{target_id}/{action}` | Superadministrador: restaurar o retirar una publicación reportada. |
| `GET /api/v1/services` | Oficios del barrio con su promedio de estrellas. Orden: mejor promedio → más calificaciones → más recientes. |
| `POST /api/v1/services` | Publica un servicio a nombre del usuario de la sesión (vecinos y comerciantes). |
| `POST /api/v1/services/endorse` | Registra un visto bueno y, opcionalmente, estrellas, comentario y foto. Un visto bueno por vecino y servicio: si ya existe, se actualiza (upsert). |
| `GET /api/v1/services/mine` | Servicios publicados por el usuario de la sesión. |
| `GET /api/v1/services/{service_id}/endorsements` | Vistos buenos y reseñas de un servicio. |
| `GET /api/v1/services/{service_id}/photos` | Fotos del servicio (aparte, para que la lista y el pull pesen poco). |
| `POST /api/v1/services/{service_id}/recommendations/{rec_id}/reply` | El dueño del servicio responde una reseña. |
| `GET /api/v1/solidarity` | Favores del barrio que no están borrados (se puede filtrar por tipo: SOLICITO_AYUDA u OFREZCO_AYUDA). |
| `POST /api/v1/solidarity` | Publica un favor a nombre del usuario de la sesión. |
| `DELETE /api/v1/solidarity/{post_id}` | Borra un favor. Solo quien lo publicó. |
| `GET /api/v1/solidarity/{post_id}` | Un favor del barrio por su id. |
| `GET /api/v1/solidarity/{post_id}/comments` | Comentarios públicos de un favor. |
| `POST /api/v1/solidarity/{post_id}/comments` | Agrega un comentario público al favor. |
| `DELETE /api/v1/solidarity/{post_id}/comments/{comment_id}` | Borra un comentario. Solo su autor. |
| `PATCH /api/v1/solidarity/{post_id}/coordinate` | "Voy a ayudar": el usuario se ofrece para el favor. No se puede en el propio. |
| `GET /api/v1/solidarity/{post_id}/photo` | La foto va aparte para que el muro y el pull pesen poco. |
| `GET /api/v1/solidarity/{post_id}/photos` | Todas las fotos del favor (hasta 4). Las apps viejas usan /photo (la primera). |
| `GET /api/v1/solidarity/{post_id}/reviews` | Calificaciones entre vecinos de un favor terminado. |
| `POST /api/v1/solidarity/{post_id}/reviews` | Solo cuando el favor está COMPLETADO: el autor califica a quien ayudó y quien ayudó califica al autor. Una reseña por persona y favor. |
| `GET /api/v1/sync/pull` | Cambios del barrio desde el último pull + estado del barrio (Modo Emergencia). |
| `POST /api/v1/sync/push` | Recibe los cambios hechos sin internet (lote) y los aplica con "gana el último" (LWW). Devuelve los rechazados con su motivo. |
| `GET /api/v1/tenants/by-code/{code}` | Público (sin sesión): confirma a qué barrio pertenece un código de invitación antes de registrarse ("Te vas a unir a: ..."). Solo devuelve nombre y centro; limitado a 30 consultas cada 5 minutos por IP para que no se adivinen códigos. |
| `GET /api/v1/tenants/current` | Datos del barrio del header `X-Tenant-ID` (nombre, centro y Modo Emergencia). |
| `PATCH /api/v1/tenants/emergency-toggle` | Activa o desactiva el Modo Emergencia para TODO el barrio. |
| `GET /api/v1/tenants/invite-code` | Código para invitar vecinos al barrio de la sesión. |
| `DELETE /api/v1/users/me` | Borra la cuenta del vecino autenticado (derecho de cancelación, Ley 29733). • Sus datos personales se borran (nombre, correo, teléfono, redes, fotos, Google). • Su contenido se marca como borrado (is_deleted) para que el pull lo quite de todos los celulares del barrio, y se le quitan las fotos. • El token deja de servir: el middleware rechaza usuarios borrados. • El correo queda libre para crear otra cuenta. |
| `GET /api/v1/users/me` | Perfil completo del vecino autenticado (redes y perfil de publicador incluidos). |
| `WEBSOCKET /api/v1/ws/chat` | Canal en tiempo real: el teléfono se conecta con su token y recibe al instante los mensajes de sus conversaciones. Los WebSocket no pasan por el middleware HTTP: la sesión se valida aquí. |
| `GET /health` | Comprueba de verdad la base de datos y si faltan migraciones. |
| `GET /health/live` | Liveness probe that does not wake the external PostgreSQL database. |

---

## App (Flutter)

### App: Arranque de la app

#### `mi_barrio_app/lib/main.dart`

- `class MiBarrioApp extends StatefulWidget`: La app: tema (día o emergencia), sincronización y la pantalla según la sesión.

### App: Núcleo (core): base de datos local, sincronización, red, sesión y diseño

#### `mi_barrio_app/lib/core/auth/auth_session_store.dart`

- `class AuthSessionStore`: Guarda la sesión (token y datos del usuario) en el teléfono con SharedPreferences. Avisa por [onSessionExpired] cuando el servidor rechaza el token (401).
  - `static String? reasonFrom(String body)`: Motivo de un 401 que vale la pena mostrar (cuenta suspendida). null si solo venció la sesión. [body] es el cuerpo JSON de la respuesta.

#### `mi_barrio_app/lib/core/barrio_context/emergency_mode_provider.dart`

- `class EmergencyModeProvider`: Estado global del Modo Emergencia. Estado efectivo = bandera del barrio (la activa la junta vecinal: `tenants.is_emergency_active`, llega por el pull) **o** el interruptor ⚠ del vecino (solo cambia SU vista: tema naranja, filtros de emergencia y el botón "Ayuda"; no avisa a nadie). Si la junta la activó, el interruptor queda bloqueado en encendido. Uso en la UI:
  - `ValueListenable<bool> get isActive`: true si la app debe mostrarse en Modo Emergencia.
  - `ValueListenable<bool> get isLockedByTenant`: true si la emergencia la activó la junta vecinal (interruptor bloqueado).
  - `bool get localToggle`: Lo que eligió el vecino en el interruptor ⚠.
  - `Future<void> load() async`: Carga la última bandera guardada. Llamar una vez al iniciar la app.
  - `Future<void> setLocal(bool value) async`: Interruptor ⚠ de la barra superior. No hace nada si la junta ya activó la emergencia (queda encendido).
  - `Future<void> setTenantFlag(bool value`: Bandera del barrio recibida del servidor. Con [tenantId] además se guarda en el teléfono (ver [_tenantFlagKey]).

#### `mi_barrio_app/lib/core/barrio_context/tenant_session.dart`

Sesión del barrio (tenant) y del vecino que inició sesión.

Todos los valores vienen del servidor al iniciar sesión ([applyAuthenticatedUser]); la app no trae barrios ni usuarios fijos. Sin sesión los campos quedan vacíos ([hasNeighborhood] = false).

- `class TenantSession`: Sesión del barrio (tenant) y del vecino que inició sesión. Todos los valores vienen del servidor al iniciar sesión ([applyAuthenticatedUser]); la app no trae barrios ni usuarios fijos. Sin sesión los campos quedan vacíos ([hasNeighborhood] = false).
  - `String role`: Rol de API actual: VECINO, COMERCIANTE, ADMIN_BARRIO o SUPER_ADMIN.
  - `bool get hasNeighborhood`: true si hay un vecino con barrio en sesión.
  - `void applyPlatformAdmin(String authenticatedUserId)`: El superadministrador no pertenece a ningún barrio.

#### `mi_barrio_app/lib/core/database_sqlite/history_dao.dart`

- `class HistoryCounts`: Cuántos registros tiene el vecino en cada pestaña de "Mi historial".
- `class HistoryDao`: "Mi historial": lo que publicó el vecino, leído solo de SQLite (sin red). Incluye lo que todavía no se sube (PENDING / FAILED), para que la pantalla muestre el chip de sincronización de cada ítem. Nunca muestra borrados ni datos de otro barrio. Orden: lo más reciente primero.
  - `Future<List<LocalServiceModel>> myServices(String tenantId, String userId) async`: Oficios que ofrezco (como comerciante).
  - `Future<List<SolidarityPostModel>> myPosts(String tenantId, String userId) async`: Favores que publiqué en el muro (incluye los COMPLETADO).
  - `Future<List<VulnerableReport>> mySos(String tenantId, String userId) async`: Pedidos de ayuda (SOS) que hice.
  - `Future<HistoryCounts> counts(String tenantId, String userId) async`: Contador para las 3 pestañas (Mis servicios / Mis favores / Mis SOS).

#### `mi_barrio_app/lib/core/database_sqlite/local_id.dart`

- `class LocalId`: Identificadores generados en el teléfono, sin red. UUID v4 con generador criptográfico (`Random.secure`, el valor por defecto del paquete `uuid`): 122 bits aleatorios, por lo que dos vecinos offline no generan el mismo id al sincronizar con PostgreSQL.
  - `static String generate()`: Nuevo UUID v4 en minúsculas (formato que acepta PostgreSQL).
  - `static bool isValidV4(String value)`: true si [value] es un UUID v4 válido.
  - `static bool isUuid(String value)`: true si [value] tiene formato UUID (cualquier versión). Útil para `tenant_id` / `user_id` que puede crear el servidor.
  - `static void requireUuid(String value, String fieldName)`: Lanza [ArgumentError] si [value] no es un UUID.

#### `mi_barrio_app/lib/core/database_sqlite/record_validation.dart`

- `class RecordValidation`: Validaciones comunes antes de escribir en SQLite. Rechazan datos que el backend no aceptaría: así un registro inválido no se queda atascado en la cola de sincronización para siempre.
  - `static String requiredText(String value, String field`: Devuelve el texto sin espacios sobrantes; falla si queda vacío o largo.

#### `mi_barrio_app/lib/core/database_sqlite/sqlite_database.dart`

- `class LocalDatabase`: Instancia única de la base de datos local `mi_barrio_offline.db`. Es el motor primario de la app (Local-First): la UI lee y escribe aquí siempre, con o sin internet.
  - `Future<Database> get database`: Abre la base una sola vez, aunque varias pantallas la pidan a la vez.
  - `Future<void> resetForTesting`: Solo para tests: cierra la base actual y usa otra ruta (por ejemplo `inMemoryDatabasePath`).

#### `mi_barrio_app/lib/core/database_sqlite/sqlite_tables.dart`

Esquema local de SQLite (espejo de PostgreSQL + tablas exclusivas del móvil).

Reglas del contrato de datos (memoria técnica, sección 4): • `id` / `tenant_id`: TEXT con UUID v4 generado en el teléfono. • Booleanos: INTEGER 0/1 en SQLite (se convierten a true/false al sincronizar). • `updated_at`: TEXT ISO-8601 UTC. • `sync_status`: solo en SQLite: 'PENDING' | 'SYNCED' | 'FAILED'.

Todas las sentencias usan IF NOT EXISTS, así que son seguras de re-ejecutar (instalación nueva o actualización de una versión anterior).

- `class SqliteTables`: Esquema local de SQLite (espejo de PostgreSQL + tablas exclusivas del móvil). Reglas del contrato de datos (memoria técnica, sección 4): • `id` / `tenant_id`: TEXT con UUID v4 generado en el teléfono. • Booleanos: INTEGER 0/1 en SQLite (se convierten a true/false al sincronizar). • `updated_at`: TEXT ISO-8601 UTC. • `sync_status`: solo en SQLite: 'PENDING' | 'SYNCED' | 'FAILED'. Todas las sentencias usan IF NOT EXISTS, así que son seguras de re-ejecutar (instalación nueva o actualización de una versión anterior).
  - `static const int schemaVersion`: Versión actual del esquema. Súbela al agregar tablas o columnas y añade el paso correspondiente en [migrations].
  - `static const createPostPhotoList`: Fotos de favores (hasta 4, en orden). Reemplaza a `post_photos`, que guardaba solo una (se copia al actualizar).
  - `static const createPostPhotos`: Fotos de favores (aparte: el pull reemplaza la fila del favor y no trae la foto; así no se pierde la que ya se descargó o se tomó aquí).
  - `static const createContentReports`: Reportes que hizo ESTE vecino (se suben por el sync). Sirven también para ocultarle lo que reportó y para no dejarlo reportar dos veces.
  - `static const createServicePhotos`: Fotos de servicios (aparte: el pull no las trae y reemplaza la fila del servicio). Hasta 4 por servicio, en orden ([position] 0..3).
  - `static const createNeighborEndorsements`: Calificación con estrellas (reemplaza al "Visto Bueno"). Una por vecino y servicio: el id es UUID v5(service_id + endorser_user_id).
  - `static const createUsers`: Perfil del vecino (módulo "Tú").
  - `static const createAppSettings`: Preferencias locales (ej. toggle de emergencia del vecino).
  - `static const createSyncOutbox`: Cola de mutaciones pendientes de subir (Outbox Pattern).
  - `static const createSyncState`: Puntero de la última descarga incremental por barrio.
  - `static const createVulnerableReports`: Pedidos de ayuda (SOS). Se guardan al instante sin red (Sprint 8).
  - `static const createSupportGroups`: Grupos de apoyo del barrio (Sprint 11). Solo bajada: los registra la junta en el servidor y el teléfono los guarda para verlos sin internet.
  - `static const List<String> createAll`: Esquema completo para una instalación nueva.
  - `static const Map<int, List<String>> migrations =`: Pasos de actualización: clave = versión destino. v1 (Sprint 1): solidarity_posts, sync_outbox, sync_state. v2 (Sprint 2): + local_services + índices. v3 (Sprint 5): + neighbor_endorsements, users, app_settings. v4 (Sprint 8): + vulnerable_reports (SOS sin red). v5 (Sprint 11): + support_groups (grupos de apoyo sin red). v6 (Sprint 12): + users.email_contacto (correo de contacto del perfil). v7 (Sprint 12): + local_services.contact_phone / contact_whatsapp (contacto del comerciante; lo manda el servidor en el pull). v8 (Sprint 13): favores con autor, contacto, foto y coordinador + post_photos. v9 (Sprint 13): servicios con precio y fotos (service_photos); reseñas con nombre. v10: servicios Pedir/Brindar + insignia + reportes (content_reports). v11: varias fotos por favor (post_photo_list) + datos del pedido de ayuda.
  - `static const Map<int, Map<String, Map<String, String>>> addedColumns =`: Columnas nuevas en tablas existentes, por versión destino. Se agregan solo si faltan (SQLite no tiene ADD COLUMN IF NOT EXISTS).

#### `mi_barrio_app/lib/core/database_sqlite/sync_outbox_dao.dart`

- `class OutboxOperation`: Operaciones permitidas en la cola (contrato del endpoint /sync/push).
- `class SyncOutboxDao`: Cola de cambios pendientes de subir (outbox): lo que se hace sin internet se guarda aquí y la sincronización lo envía al servidor cuando hay conexión.
  - `static Stream<String> get onQueued`: Avisa (con el tenant) cada vez que se encola una mutación. El SyncCoordinator lo escucha para sincronizar apenas haya red.
  - `Future<int> countPending(String tenantId) async`: Cantidad de registros con cambios sin subir en el barrio (para el aviso "Tienes N cambios sin sincronizar"). Editar 3 veces el mismo favor cuenta 1.
  - `Future<void> queueMutation`: Encola una mutación pendiente de subir. Pasa [executor] (una transacción) para que el registro y su entrada en la cola se guarden juntos: si la app se cierra a la mitad, no queda un registro PENDING sin su mutación (ni al revés).
  - `Future<void> rememberPendingOwner`: Recuerda de quién son los cambios pendientes cuando la sesión vence sin cerrar sesión a propósito: si vuelve a entrar la MISMA persona, se suben.
  - `Future<void> clearUserData`: Al cerrar sesión (o al entrar otra persona): borra lo PRIVADO de la cuenta. • El perfil (`users`) se borra siempre. • De favores, servicios, calificaciones y SOS se borra solo lo que NUNCA llegó al servidor (PENDING / FAILED). Lo ya publicado (SYNCED) es del barrio y se queda: el pull es incremental y no lo volvería a bajar, así que el siguiente vecino de este teléfono dejaría de verlo. • La cola del barrio se vacía (lo pendiente era de esta cuenta).

#### `mi_barrio_app/lib/core/location/gps_service.dart`

- `enum GpsError`: Por qué no se pudo obtener la ubicación.
- `class GpsException implements Exception`: Error del GPS con su motivo ([GpsError]) y un mensaje para mostrar.
- `class GpsCoordinates`: Un punto en el mapa (latitud y longitud) obtenido del GPS.
- `typedef LocationServiceCheck`: ¿Está encendido el GPS? (funciones del GPS reemplazables en las pruebas)
- `typedef LocationPermissionCheck`: Pide o consulta el permiso de ubicación.
- `typedef CurrentPositionRequest`: Pide la posición actual al GPS.
- `class GpsService`: Obtiene la ubicación del sensor nativo; no necesita conexión a internet.

#### `mi_barrio_app/lib/core/moderation/content_filter.dart`

- `class ContentFilter`: Groserías y discurso de odio → asteriscos ("p***"). Usa la MISMA lista que el servidor (assets/moderation/offensive_words.json, copia de mi_barrio_backend/app/core/offensive_words.json). El servidor censura siempre antes de guardar; aquí se hace mientras se escribe para que el vecino vea al instante qué no se va a publicar.
  - `static Future<void> load() async`: Se llama una vez al abrir la app. Si falla, la app sigue (el servidor censura igual).
  - `static String normalize(String word)`: Igual que en el servidor: minúsculas, sin tildes, 4→a…, sin repetidas.
  - `static String censor(String text`: [onlyFinishedWords]: mientras se escribe, la última palabra puede estar a medias ("put" → "putamente"…), así que no se toca hasta que termine.
- `class OffensiveWordsFormatter extends TextInputFormatter`: Para los campos donde se escribe algo que verán otros vecinos: al terminar cada palabra ofensiva la cambia por asteriscos.

#### `mi_barrio_app/lib/core/network/api_client.dart`

- `class ApiConfig`: Dirección del backend FastAPI. Por defecto, el servidor de PRODUCCIÓN en Render (funciona desde cualquier red: datos móviles, otro Wi-Fi, APK de demo). Para desarrollar con el backend local, fijarlo al compilar: flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000 (emulador Android) flutter run --dart-define=API_BASE_URL=http://localhost:8000 (Linux / Windows) flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000 (celular, IP de la PC)
  - `static const timeout`: Render gratis tarda ~50 s en despertar: con 30 s el primer login fallaba.
  - `static const coldStartTimeout`: El plan gratis de Render apaga el servidor tras 15 min sin uso y tarda ~1 minuto en volver: login, registro y sesión esperan más.
- `class ApiClient`: Cliente HTTP que agrega siempre el header `X-Tenant-ID` y un timeout.
  - `static Object? decodeOrThrow(http.Response response)`: Cuerpo JSON de [response]; si el estado no es 2xx lanza [Exception] con el mensaje del servidor (`detail` / `error`).
  - `Future<bool> isServerReachable`: true si el backend responde a /health/live (útil porque "tener Wi-Fi" no garantiza que el servidor sea alcanzable). /health/live no toca la base de datos, así que no espera a que Neon despierte.
  - `static void wakeUp()`: Despierta al servidor sin esperar la respuesta (al abrir la app y al volver a ella), para que esté listo cuando el vecino toque "Ingresar".

#### `mi_barrio_app/lib/core/network/connectivity_monitor.dart`

- `enum ConnectionStatus`: Si el teléfono tiene red o no.
- `class ConnectivityMonitor`: Indica si el teléfono TIENE una red (Wi-Fi, datos, etc.). Es solo una pista: tener red no garantiza llegar al servidor, y el sistema a veces no avisa un cambio (app en segundo plano, VPN, anclaje USB). Por eso [refresh] vuelve a preguntar y la sincronización lo usa antes de rendirse con "Modo offline".
  - `Future<void> start() async`: Llamar una vez al inicio de la app (en main()).
  - `Future<ConnectionStatus> refresh() async`: Vuelve a preguntar al sistema (al volver a la app o antes de decir "offline"). Si el sistema no responde, se asume que hay red y que la petición HTTP decida.
  - `static ConnectionStatus toStatus(List<ConnectivityResult> results)`: En connectivity_plus 6.x los eventos son una lista de interfaces activas. Solo es "offline" si no hay NINGUNA (lista vacía o solo `none`): una VPN, un anclaje (`other`) o bluetooth también pueden llevar internet.

#### `mi_barrio_app/lib/core/realtime/chat_socket.dart`

- `enum RealtimeStatus`: Estado de la conexión en tiempo real (para el aviso en el chat).
- `class ChatSocket`: Canal en tiempo real del chat (favores y servicios, WebSocket `/api/v1/ws/chat`). • Se conecta cuando hay al menos un chat abierto ([acquire]) y se cierra cuando ya no ([release]). • Si se corta (sin señal, servidor reiniciándose) reintenta solo, cada vez con más espera (1, 2, 4… hasta 30 s). • Mantiene viva la conexión con un "ping" cada 25 s. • Los mensajes se ENVÍAN por REST (quedan guardados aunque el otro no esté conectado); por aquí solo se RECIBEN al instante.
  - `static WebSocketChannel Function(Uri uri) connector =`: Para los tests: reemplaza la conexión real.
  - `Stream<ChatMessage> get messages`: Mensajes nuevos de cualquier chat del vecino.
  - `void injectForTesting(ChatMessage message)`: Solo para tests: simula un mensaje recibido por el WebSocket.

#### `mi_barrio_app/lib/core/sync_manager/pending_changes.dart`

- `class PendingChanges`: Cambios hechos sin internet que todavía no llegaron al servidor. Para el aviso de "Cerrar sesión" (pantalla Tú):
  - `static Future<int> count(String? tenantId`: Registros pendientes del barrio. Sin barrio (null) → 0.
  - `static String? logoutWarning(int count)`: Texto del aviso al cerrar sesión, o null si no hay nada pendiente.

#### `mi_barrio_app/lib/core/sync_manager/sync_coordinator.dart`

- `enum SyncPhase`: Estado visible de la sincronización (para la barra "Modo offline / Sincronizado").
- `class SyncCoordinator`: Orquesta cuándo sincronizar (Checkpoint 1): 1. Al abrir la app. 2. Cuando vuelve internet. 3. Poco después de cada publicación nueva (si hay red). 4. Cada [interval] como respaldo. Nunca corre dos sincronizaciones a la vez; si llega un pedido durante una, se hace una ronda más al terminar. Reintentos (Sprint 12): si el SERVIDOR falla (5xx, sin respuesta, tiempo agotado) estando con red, se reintenta a los 2, 4, 8 y 16 s. Después sigue el ritmo normal ([interval]). Cualquier sincronización exitosa reinicia la cuenta. No se reintenta sin red (lo hace la vuelta de internet), con la sesión vencida (401) ni por datos rechazados (reintentar no los arregla).
  - `static const defaultRetryDelays`: Esperas entre reintentos: 2, 4, 8 y 16 segundos.
  - `final ValueNotifier<SyncPhase> phase`: Estado actual, para que la UI lo muestre (Sprint 10).
  - `final ValueNotifier<DateTime?> lastSuccess`: Fecha de la última sincronización exitosa (push + pull).
  - `final ValueNotifier<Duration?> nextRetry`: Espera del próximo reintento programado (null = ninguno). Para la UI: "Reintentando en 4 s…".
  - `int get retryAttempt`: Cuántos reintentos seguidos se programaron desde el último éxito.
  - `Future<void> start`: Llamar una vez en main(), después de `ConnectivityMonitor.instance.start()`.
  - `Future<void> syncNow() async`: Sincroniza ahora (push y luego pull). Seguro de llamar muchas veces.
  - `void setInterval(Duration interval)`: Ajusta la frecuencia (Sprint 8: 15 s en emergencia, 60 s en modo normal).

#### `mi_barrio_app/lib/core/sync_manager/sync_worker.dart`

- `class PushResult`: Resultado de subir los cambios pendientes.
  - `final int batchCount`: Cuántos envíos a `/sync/push` se hicieron (lotes de [SyncWorker.maxBatch]).
  - `final bool retryable`: Falla TEMPORAL (servidor caído o lento, sin respuesta): vale la pena reintentar pronto. Un 401 o un dato rechazado no se arreglan reintentando.
  - `final bool httpFailed`: El servidor no respondió 200: se detienen los lotes siguientes.
- `class PullResult`: Resultado de descargar cambios del servidor.
  - `final bool retryable`: Ver [PushResult.retryable].
- `bool isTransientHttpStatus(int status)`: Respuestas HTTP que suelen arreglarse solas: 408 (tiempo agotado), 429 (demasiadas peticiones) y 5xx (el servidor falló o se está reiniciando).
- `class SyncWorker`: Habla con el servidor de sincronización: sube la cola de cambios (push) y baja lo nuevo del barrio (pull). Marca como reintentables los errores temporales (408, 429, 5xx); `SyncCoordinator` decide cuándo reintentar.
  - `static const maxBatch`: Máximo de cambios por envío que acepta `/sync/push` (si se pasa: 413).
  - `Future<PushResult> pushLocalChanges(String tenantId) async`: Sube la cola en orden y en lotes de [maxBatch]. Cada lote se confirma en SQLite apenas responde el servidor: si se corta la red a la mitad, lo ya enviado no se repite y el resto queda pendiente. Si un lote falla (sin red, 401, 5xx) se detiene: los lotes siguientes esperan al próximo sync para respetar el orden de los cambios.
  - `Future<PullResult> pullRemoteChanges(String tenantId) async`: Descarga lo que cambió en el servidor desde la última vez y lo guarda en SQLite. Si un registro tiene cambios locales todavía sin subir (PENDING), NO se pisa: primero se sube con el push y el servidor decide con Last-Write-Wins.

#### `mi_barrio_app/lib/core/ui_kit/app_select_field.dart`

- `class AppSelectOption<T>`: Una opción de [AppSelectField]: valor, texto y un ícono opcional.
- `class AppSelectField<T> extends StatelessWidget`: Campo para elegir una opción: se toca y se abre una hoja inferior con la lista (más fácil de usar que un menú desplegable en pantallas chicas).

#### `mi_barrio_app/lib/core/ui_kit/app_theme.dart`

- `class AppPalette`: Paleta de Mi Barrio (v3, teoría del color + daltonismo). • **Marca**: verde azulado para la economía local diaria, naranja para emergencia, celeste suave para etiquetas. • **v3 (aprobada por el equipo)**: el verde `#1E7A2E` y el naranja `#C2381B` tenían la misma luminosidad y, para un daltónico (deuteranopía), los dos se veían oliva: el cambio a emergencia casi no se notaba. El verde azulado `#0F766E` se ve gris azulado y se distingue del naranja. • **Acción accesible**: el mismo tono, más oscuro, para botones y texto. Los tonos de marca se usan en íconos, bordes y franjas (3:1, permitido). `test/ui_kit/app_theme_test.dart` verifica todos los contrastes (WCAG AA).
- `class MiBarrioColors extends ThemeExtension<MiBarrioColors>`: Colores que dependen del modo, accesibles desde cualquier widget: `MiBarrioColors.of(context)`.
  - `final Color brand`: Color de marca del modo actual (verde o naranja): íconos, bordes, franjas.
  - `final Color accentText`: Texto/ícono de acento legible sobre blanco y sobre [accentSoft].
  - `final Color accentSoft`: Fondo suave del acento (selección, chips activos).
- `class AppTheme`: Temas de la app (día y emergencia) con áreas táctiles de 48 px y buen contraste.

#### `mi_barrio_app/lib/core/ui_kit/dev_tools.dart`

- `class DevTools`: Herramientas de desarrollo (interruptor 🐞 de emergencia, avisos internos). Nunca aparecen en el build de demo: en release/profile están apagadas, y en debug también se apagan si el build apunta a un servidor real (`--dart-define=API_BASE_URL=...`) o si se marca `--dart-define=DEMO_BUILD=true`.

#### `mi_barrio_app/lib/core/ui_kit/done_confirmation.dart`

- `class DoneConfirmation`: Confirmación grande y simple después de publicar: "¡Listo!" + qué pasó. Se ve sin leer mucho (ícono de check) y aclara que funciona sin señal.

#### `mi_barrio_app/lib/core/ui_kit/emergency_switch_tile.dart`

- `class EmergencySwitchTile extends StatelessWidget`: Interruptor de emergencia de los formularios para publicar. Encendido se ve naranja (fondo, ícono y switch); viene encendido cuando la app está en modo emergencia. • Ofrezco: "Atiendo en emergencias". • Necesito: "Es una emergencia".
  - `final bool isNeed`: true = es un pedido (Necesito); false = es una oferta (Ofrezco).

#### `mi_barrio_app/lib/core/ui_kit/emergency_toggle.dart`

- `class EmergencyToggle extends StatelessWidget`: Interruptor grande para activar o desactivar el Modo Emergencia del barrio.

#### `mi_barrio_app/lib/core/ui_kit/global_sync_status_bar.dart`

- `class GlobalSyncStatusBar extends StatefulWidget`: Barra de estado global: en todas las pestañas, debajo de la barra superior. Solo aparece cuando hay algo que contar: sin señal, error o reintento. Cuando todo está bien no ocupa espacio; al resolverse un problema muestra "Sincronizado" unos segundos ([recoveredDuration]) y se oculta. Siempre usa ícono + texto (nunca solo color) y el texto puede ocupar varias líneas para que funcione con letra al 200 %.
  - `final ValueListenable<SyncPhase>? phase`: Fuentes del estado. En la app son las del [SyncCoordinator]; los tests pasan sus propios notifiers.
  - `static const recoveredDuration`: Cuánto se ve "Sincronizado" después de resolverse un problema.

#### `mi_barrio_app/lib/core/ui_kit/icon_scale.dart`

- `double escalaIcono(BuildContext context)`: Cuánto crecen los íconos con la letra del teléfono (1 a 1,6 veces). Con "tamaño de fuente" grande el texto crece pero los íconos no: un adulto mayor veía palabras enormes junto a íconos diminutos.

#### `mi_barrio_app/lib/core/ui_kit/location_map.dart`

- `class LocationMap extends StatelessWidget`: Mapa pequeño de un lugar (ej. dónde atiende un comerciante). Con internet muestra las calles (OpenStreetMap); sin internet, el marcador sobre un fondo liso. Se puede mover y hacer zoom con los dedos.
  - `final void Function(double lat, double lng)? onTapPoint`: Si no es null, tocar el mapa mueve el punto (elegir dónde atiendes).
  - `final String label`: Para el lector de pantalla: "Ubicación de Gasfitería Don Pedro".
  - `final double? myLat`: Ubicación del vecino (punto azul), si se conoce.
  - `final bool? showStreets`: Calles de OpenStreetMap (por defecto sí, salvo en los tests: sin red).

#### `mi_barrio_app/lib/core/ui_kit/main_navigation_shell.dart`

- `class ShellTab`: Una pestaña de la barra inferior: id, texto e íconos.
  - `final bool showsPublish`: false = la pestaña no muestra el botón flotante "Publicar"/"Pedir ayuda".
- `class ShellTabs`: Las pestañas de la barra inferior y su orden.
- `class MainNavigationShell extends StatefulWidget`: Pantalla principal con la barra inferior (Servicios, Apoyo, Mapa, Tú…), el aviso de sin conexión y el de Modo Emergencia.
  - `final ValueListenable<SyncPhase>? syncPhase`: Estado de sync para la barra global (por defecto, el del SyncCoordinator).
  - `final Future<bool> Function()? onPublish`: Botón "Ayuda" en modo emergencia (pedido de ayuda). En el día a día, "Publicar" abre el formulario de la pestaña (Servicios o Apoyo).
  - `static const apoyoTabIndex`: Índices de pestañas (orden de [ShellTabs.all]).
  - `static const emergencyPreviewSwitchKey`: Interruptor ⚠ de la barra (modo emergencia del vecino).

#### `mi_barrio_app/lib/core/ui_kit/photo_picker.dart`

- `typedef PhotoPicker`: Elige una foto ya comprimida (máx. 800 px, calidad 60). Los tests la reemplazan.
- `PhotoPicker appPhotoPicker`: Selector de fotos de toda la app (reemplazable en pruebas).
- `Future<String?> pickPhotoB64`: Pregunta "Cámara o Galería" y devuelve la foto en base64 (null si se canceló). Lanza [StateError] si la foto supera [maxB64Length].

#### `mi_barrio_app/lib/core/ui_kit/podium_frame.dart`

- `class PodiumFrame extends StatelessWidget`: Marco del podio de emergencia: borde de color de énfasis y chip "Prioridad N" con ícono y texto (no depende solo del color).
  - `final int priority`: 1, 2 o 3.

#### `mi_barrio_app/lib/core/ui_kit/publish_action.dart`

- `class PublishAction extends InheritedWidget`: Abre el formulario de "Publicar" de la pestaña actual desde cualquier parte de ella (por ejemplo, el botón de una lista vacía). Lo pone la barra de navegación principal; fuera de ella (tests, pantallas sueltas) no existe y las listas vacías simplemente no muestran el botón.

#### `mi_barrio_app/lib/core/ui_kit/quick_publish_fab.dart`

- `class QuickPublishFab extends StatelessWidget`: Botón flotante (+) de publicación rápida — Clic 1 del flujo de 3 clics. • Modo Día a Día: "Publicar" (verde). • Modo Emergencia: "Ayuda" (naranja, solo texto). Extendido con texto (no solo ícono) para que cualquier vecino, incluidos adultos mayores, entienda qué hace sin adivinar.

#### `mi_barrio_app/lib/core/ui_kit/safe_image.dart`

- `class SafeMemoryImage extends StatelessWidget`: Foto guardada en el teléfono. Si los datos están dañados muestra un ícono en vez de romper la pantalla.

#### `mi_barrio_app/lib/core/ui_kit/search_filter_bar.dart`

- `class FilterOption`: Una opción (píldora) dentro de un grupo de filtros.
  - `final String value`: Valor interno (el mismo que usan los datos, p. ej. `OFREZCO_AYUDA`).
- `class FilterGroup`: Grupo de filtros: subtítulo + píldoras.
  - `const FilterGroup.toggle`: Interruptor (encendido / apagado) en lugar de píldoras. Encendido se guarda como `{FilterGroup.on}`.
  - `final bool multiple`: true = se pueden elegir varias píldoras; false = solo una.
  - `final String? allLabel`: Si existe, se muestra primero una píldora "Todas" que queda elegida cuando el grupo no tiene ningún filtro (solo en grupos de una opción).
- `bool isToggleOn(FilterSelection selection, String id)`: true si el interruptor [id] está encendido en [selection].
- `typedef FilterSelection`: Filtros elegidos: id del grupo → valores elegidos. Vacío = sin filtros.
- `int activeFilterCount(FilterSelection selection)`: Cuántos grupos tienen al menos un filtro activo.
- `class SearchFilterBar extends StatelessWidget`: Buscador + botón de filtros. Es el mismo en Servicios y en Apoyo.
- `class FilterButton extends StatelessWidget`: Botón de filtros sin borde: gris oscuro; con filtros activos, fondo gris claro y un número (el estado no se comunica solo con color).
- `Future<FilterSelection?> showFilterDialog`: Modal flotante centrado con los grupos de filtros. Devuelve la nueva selección al tocar "Aplicar", o null si se cierra.
- `class FilterPill extends StatelessWidget`: Píldora de filtro: borde gris; elegida, verde agua con ✓. Usa los colores del modo actual (en emergencia, el naranja suave).
- `class DistanceFilter`: Filtro de distancia compartido (desde el punto de referencia del barrio).
  - `static bool matches(Set<String>? selected, double km)`: true si [km] cumple el filtro elegido (o si no hay filtro).

#### `mi_barrio_app/lib/core/ui_kit/splash_screen.dart`

- `class SplashScreen extends StatefulWidget`: Pantalla al abrir la app mientras se lee la sesión guardada. En vez de un indicador solo, muestra el logo y dice qué pasa. Si tarda (servidor despertando o señal débil), avisa que entrará igual con lo guardado en el teléfono, para que nadie piense que la app se colgó.
  - `static const slowAfter`: Después de este tiempo se muestra el aviso de conexión lenta.

#### `mi_barrio_app/lib/core/ui_kit/star_rating_display.dart`

- `class StarRatingDisplay extends StatelessWidget`: Muestra una calificación con estrellas (solo lectura), con texto para lectores de pantalla.

#### `mi_barrio_app/lib/core/ui_kit/star_rating_input.dart`

- `class StarRatingInput extends StatelessWidget`: Permite elegir de 1 a 5 estrellas tocándolas.

#### `mi_barrio_app/lib/core/ui_kit/sync_status_chip.dart`

- `enum SyncChipStatus`: Estado de sincronización de un registro: pendiente, sincronizado o con error.
- `class SyncStatusChip extends StatelessWidget`: Etiqueta pequeña que dice si un cambio ya se subió al servidor o sigue pendiente.

### App: Utilidades compartidas

#### `mi_barrio_app/lib/shared/contact_launcher.dart`

- `class ContactLauncher`: Abre el marcador del teléfono o WhatsApp con un número del barrio. Los números peruanos de 9 dígitos sin código de país se completan con +51 (WhatsApp exige el número internacional).
  - `static String normalize(String raw)`: Solo los dígitos (y un "+" inicial si lo había).
  - `static String international(String raw)`: Número internacional sin "+", como lo pide wa.me: 51987654321.
  - `static Future<bool> call(String raw)`: Abre el marcador. Devuelve false si el teléfono no pudo (ej. tablet sin SIM).
  - `static Future<bool> whatsapp(String raw`: Abre WhatsApp (o el navegador si no está instalado).
  - `static Uri directionsUri(double lat, double lng)`: Ruta "Cómo llegar" (a pie) hasta un punto. Abre Google Maps o la app de mapas del teléfono; si no hay ninguna, el navegador.

#### `mi_barrio_app/lib/shared/emergency_ranking.dart`

- `class Ranked<T>`: Un elemento ya ordenado por el ranking de emergencia. [position] empieza en 1. [priority] es 1, 2 o 3 si el elemento va en el podio "Prioridad 1-3" (la UI muestra el chip con ese número); si no, null.
  - `final double? distanceKm`: Distancia al vecino; null si no se conoce su ubicación.
- `class EmergencyRanking`: Orden de "qué ayuda primero" durante una emergencia. Funciona sin internet: solo usa lo que ya está en SQLite y la ubicación del vecino. Uso en pantalla:
  - `static List<Ranked<LocalServiceModel>> rankServices`: Oficios: disponible en emergencia → categoría SOPORTE_EMERGENCIA → mejor promedio de estrellas (sin calificar va al final) → más cerca. Los borrados no aparecen. Si [lat]/[lng] son null no se usa la distancia.
  - `static List<Ranked<SolidarityPostModel>> rankPosts`: Favores: contexto de emergencia o RECURSO_CRITICO → DISPONIBLE antes que EN_COORDINACION → más cerca → más reciente. Los borrados no aparecen. Los COMPLETADO ya no necesitan ayuda: van siempre al final y nunca ocupan el podio.
  - `static bool isUrgentPost(SolidarityPostModel post)`: Un favor es urgente si se publicó en emergencia o es un recurso crítico.

#### `mi_barrio_app/lib/shared/local_distance.dart`

- `class LocalDistance`: Distancia entre dos coordenadas GPS, sin internet ni servicios de mapas.
  - `static double km(double lat1, double lng1, double lat2, double lng2)`: Distancia en kilómetros (fórmula de haversine).
  - `static String label(double km)`: Texto corto para la UI: "350 m" o "2,4 km".

### App: Cuentas: login, registro, Google, correo y administradores

#### `mi_barrio_app/lib/features/auth_barrio/data/datasources/auth_remote_datasource.dart`

- `class AuthException implements Exception`: Error de cuentas con un mensaje en palabras simples para mostrar al vecino y, si lo hay, el código HTTP del servidor.
- `class AuthRemoteDatasource`: Llamadas al servidor de cuentas: login, registro, Google, códigos al correo, recuperar contraseña, borrar cuenta y barrios del superadministrador. Traduce los errores de red a mensajes que se entienden.
  - `Future<Map<String, dynamic>> googleLogin`: Entrar (o crear la cuenta) con el ID token de Google. La primera vez el servidor responde 428 si falta el código del barrio.
  - `Future<String> sendVerificationCode(String email) async`: Envía (otra vez) el código de 6 dígitos para confirmar el correo.
  - `Future<Map<String, dynamic>> verifyEmail`: Confirma el correo con el código. Devuelve la sesión actualizada.
  - `Future<String> requestPasswordReset(String email) async`: "Olvidé mi contraseña": envía un código al correo (si la cuenta existe).
  - `Future<Map<String, dynamic>> resetPassword`: Cambia la contraseña con el código y deja la sesión iniciada.
  - `Future<String?> lookupNeighborhoodName(String joinCode) async`: Nombre del barrio de un código de invitación (ruta pública, sin sesión). null = el código no existe. Lanza [AuthException] si no hay conexión.
  - `Future<Map<String, dynamic>> getCurrentUser`: [timeout]: al abrir la app se usa uno corto para no dejar al vecino esperando si el servidor está despertando (entra con lo guardado).
  - `Future<Map<String, dynamic>> setPassword`: Quien entró con Google crea su contraseña. Devuelve la sesión actualizada.
  - `Future<void> deleteUnverifiedAccount(String token) async`: "Volver para cambiar datos": borra la cuenta que nunca confirmó su correo. Si falla (sin red), registrarse de nuevo igual reemplaza sus datos.
  - `Future<void> deleteAccount`: Borra la cuenta del vecino (DELETE /api/v1/users/me).
  - `Future<List<NeighborhoodSummary>> listNeighborhoods(String token) async`: Barrios de la plataforma (solo SUPER_ADMIN).

#### `mi_barrio_app/lib/features/auth_barrio/data/datasources/google_sign_in_client.dart`

- `abstract class GoogleIdTokenSource`: Pide a Google un "ID token" para mandarlo al servidor. Se configura al compilar con el **Web client ID** del proyecto de Google Cloud (el mismo que el servidor tiene en `GOOGLE_CLIENT_IDS`):
  - `bool get isAvailable`: false en Windows/web de escritorio: ahí no hay "Entrar con Google".
  - `Future<String?> getIdToken()`: El ID token, o null si el vecino cerró la ventana de Google. Lanza [AuthException] con un mensaje para mostrar si algo falla.
  - `Future<void> signOut()`: Cierra la sesión de Google en el teléfono (para poder elegir otra cuenta).
- `class GoogleSignInClient implements GoogleIdTokenSource`: Implementación real con el paquete google_sign_in (solo Android/iOS).
- `final googleIdTokenSourceProvider`: Reemplazable en las pruebas.

#### `mi_barrio_app/lib/features/auth_barrio/data/models/user_model.dart`

- `class UserModel extends UserEntity`: La cuenta leída del servidor o del teléfono (JSON) y guardada en la sesión.

#### `mi_barrio_app/lib/features/auth_barrio/data/repositories/auth_repository_impl.dart`

- `class AuthRepositoryImpl implements AuthRepository`: Une el servidor ([AuthRemoteDatasource]) con la sesión guardada en el teléfono ([AuthSessionStore]) y los datos locales pendientes de sincronizar.
  - `static const profileWait`: Tiempo máximo que el login espera el perfil completo; si no llega, se sigue con lo local (rol y nombre del login) y no se bloquea la entrada.
  - `static const restoreTimeout`: Cuánto se espera al servidor al abrir la app antes de entrar sin red.

#### `mi_barrio_app/lib/features/auth_barrio/domain/entities/user_entity.dart`

Rol de la cuenta: valor que usa la API y texto para mostrar.

- `enum UserRole`: Rol de la cuenta: valor que usa la API y texto para mostrar.
- `class UserEntity`: La cuenta con sesión iniciada: quién es, su barrio, su rol y si confirmó su correo.
  - `final String? email`: Correo de la cuenta (null en sesiones guardadas por versiones viejas).
  - `final bool emailVerified`: false = cuenta nueva que aún no escribió el código del correo. Las sesiones viejas y las cuentas que ya existían cuentan como verificadas.
  - `final bool hasPassword`: false = entró con Google y todavía no creó una contraseña: la app se la pide antes de seguir. Las sesiones viejas cuentan como "con contraseña".
- `class NeighborhoodProvisionEntity`: Resultado de crear un barrio y su administrador (superadministrador).
- `class NeighborhoodSummary`: Un barrio de la plataforma, como lo ve el superadministrador.

#### `mi_barrio_app/lib/features/auth_barrio/domain/repositories/auth_repository.dart`

- `abstract interface class AuthRepository`: Todo lo que la app puede hacer con cuentas. Se reemplaza por uno falso en las pruebas.
  - `Future<UserEntity> signInWithGoogle`: Entra o crea la cuenta con Google. Lanza `AuthException` con statusCode 428 si es una cuenta nueva y falta el código del barrio.
  - `Future<String> sendVerificationCode(String email)`: Envía otra vez el código de verificación. Devuelve el mensaje para mostrar.
  - `Future<UserEntity> verifyEmail`: Confirma el correo con el código y devuelve la sesión actualizada.
  - `Future<UserEntity> setPassword(String password)`: Quien entró con Google crea su contraseña (pide sesión iniciada).
  - `Future<String> requestPasswordReset(String email)`: "Olvidé mi contraseña": envía un código al correo.
  - `Future<UserEntity> resetPassword`: Cambia la contraseña con el código y deja la sesión iniciada.
  - `Future<void> deleteAccount`: Borra la cuenta en el servidor (necesita internet).
  - `Future<void> keepPendingDataFor`: Sesión vencida (401): se conservan los cambios hechos sin internet.
  - `Future<void> reconcilePendingData(UserEntity user)`: Tras iniciar sesión: si los pendientes son de otra persona se borran; si son de la misma, se conservan para subirlos.

#### `mi_barrio_app/lib/features/auth_barrio/presentation/providers/auth_provider.dart`

- `enum AuthStatus`: En qué estado está la sesión (y con qué rol), para decidir qué pantalla mostrar.
- `class AuthState`: Estado de la sesión: estado, cuenta y un mensaje de error si lo hay.
  - `const AuthState.restoring()`: Abriendo la app: se lee la sesión guardada. Es el único "cargando" que muestra la pantalla de bienvenida; al ingresar o registrarse, la pantalla sigue visible con lo escrito y su propio indicador.
- `class AuthNotifier extends StateNotifier<AuthState>`: Maneja la sesión: entrar, registrarse, Google, códigos, cerrar sesión y borrar la cuenta. Las pantallas lo usan a través de [authProvider].
  - `Future<GoogleSignInResult> signInWithGoogle`: Entra o crea la cuenta con Google. Devuelve [GoogleSignInOutcome].
  - `Future<String?> resendVerificationCode() async`: Envía otra vez el código al correo de la cuenta actual. null = enviado.
  - `Future<String?> verifyEmail(String code) async`: Confirma el correo con el código. null = listo (la app sigue sola).
  - `Future<String?> createPassword(String password) async`: Crea la contraseña de quien entró con Google. null = lista.
  - `Future<String?> requestPasswordReset(String email) async`: "Olvidé mi contraseña": pide el código. null = enviado.
  - `Future<String?> resetPassword`: Cambia la contraseña con el código y entra. null = listo.
  - `Future<String?> deleteAccount() async`: Borra la cuenta en el servidor y luego los datos del celular. null = listo.
  - `Future<void> expireSession`: [reason]: por qué se cerró (p. ej. cuenta suspendida), para mostrarlo en la pantalla de ingreso. null = la sesión simplemente venció.
- `enum GoogleSignInOutcome`: Cómo terminó "Entrar con Google".
- `class GoogleSignInResult`: Resultado de "Entrar con Google" y un mensaje si falló.
  - `final String? message`: Mensaje para el vecino cuando [outcome] es [GoogleSignInOutcome.failed].

#### `mi_barrio_app/lib/features/auth_barrio/presentation/register_draft.dart`

- `class RegisterDraft`: Lo que el vecino escribió al crear su cuenta, para "Volver para cambiar datos" (aunque cierre la app). **Nunca guarda la contraseña**: por seguridad se vuelve a escribir.
  - `final String role`: `VECINO` o `COMERCIANTE`.
  - `static bool reopenRequested`: true = al volver al inicio de sesión se abre "Crear cuenta" con el borrador (lo pide "Volver para cambiar datos").

#### `mi_barrio_app/lib/features/auth_barrio/presentation/screens/create_password_screen.dart`

- `class CreatePasswordScreen extends ConsumerStatefulWidget`: Después de registrarse (o entrar por primera vez) con Google, el vecino crea una contraseña. Así también puede entrar con correo y contraseña si pierde el acceso a Google o usa otro teléfono. Si no hay internet se puede dejar para después: en una emergencia nadie debe quedar bloqueado fuera de la app. Se vuelve a pedir al abrirla.
  - `final VoidCallback? onSkip`: "Hacerlo después" (solo aparece si falló por falta de conexión).

#### `mi_barrio_app/lib/features/auth_barrio/presentation/screens/forgot_password_screen.dart`

- `class ForgotPasswordScreen extends ConsumerStatefulWidget`: "¿Olvidaste tu contraseña?": 1) correo → 2) código + contraseña nueva. Al terminar, el vecino queda con la sesión iniciada. También sirve para crear una contraseña a quien entró con Google.

#### `mi_barrio_app/lib/features/auth_barrio/presentation/screens/login_screen.dart`

- `class LoginScreen extends ConsumerStatefulWidget`: Inicio de sesión. • Encabezado con el logo real y el color de la marca. • Campos con ícono, teclado correcto, autocompletado y "Siguiente" → "Ingresar". • Errores en lenguaje simple (nunca detalles técnicos), anunciados al lector de pantalla, que se ocultan al volver a escribir. • Si el servidor tarda (Render gratis "despierta" en ~30 s), se avisa.
  - `static const slowServerAfter`: Después de este tiempo cargando se muestra el aviso de servidor lento.
  - `static String friendlyError(String raw)`: Convierte el mensaje del servidor o de la red en uno para vecinos.

#### `mi_barrio_app/lib/features/auth_barrio/presentation/screens/neighborhood_admin_screen.dart`

- `class NeighborhoodAdminScreen extends ConsumerWidget`: Panel del administrador del barrio: Modo Emergencia, código de invitación y reportes.

#### `mi_barrio_app/lib/features/auth_barrio/presentation/screens/platform_admin_screen.dart`

- `typedef NeighborhoodsLoader`: Trae los barrios de la plataforma (lo inyectan los tests).
- `class PlatformAdminScreen extends ConsumerStatefulWidget`: Panel del superadministrador: crear barrios con su administrador y ver los barrios.
  - `final NeighborhoodsLoader? loadNeighborhoods`: Por defecto, `GET /api/v1/platform/neighborhoods` con la sesión actual.
  - `final GpsService? gps`: Para "Usar mi ubicación" (los tests pasan uno falso).

#### `mi_barrio_app/lib/features/auth_barrio/presentation/screens/register_screen.dart`

- `typedef NeighborhoodLookup`: Busca el nombre del barrio de un código (null = no existe).
- `class RegisterScreen extends ConsumerStatefulWidget`: Crear cuenta: código del barrio, rol, Google o correo y contraseña, con el aviso de términos.
  - `final NeighborhoodLookup? lookupNeighborhood`: Por defecto, `GET /api/v1/tenants/by-code/{code}` (ruta pública).

#### `mi_barrio_app/lib/features/auth_barrio/presentation/screens/verify_email_screen.dart`

- `class VerifyEmailScreen extends ConsumerStatefulWidget`: Aparece después de crear una cuenta con contraseña: hay que escribir el código de 6 dígitos que llegó al correo antes de usar la app.
  - `static const resendAfter`: Espera entre reenvíos (igual que el servidor).

#### `mi_barrio_app/lib/features/auth_barrio/presentation/widgets/account_widgets.dart`

- `class GoogleSignInButton extends StatelessWidget`: Botón "Continuar con Google" (blanco, con la G de colores, como pide Google).
- `class OrDivider extends StatelessWidget`: Separador "o" entre el formulario y el botón de Google.
- `class PasswordStrengthMeter extends StatelessWidget`: Barra de fuerza de la contraseña: Débil / Regular / Buena / Fuerte.
- `class RoleCard extends StatelessWidget`: Tarjeta grande y tocable para elegir el tipo de cuenta (en vez de un desplegable): se entiende sin leer mucho y es fácil de tocar.
- `class RoleChoice extends StatelessWidget`: Las dos tarjetas: vecino o comerciante.
- `class NeighborhoodChoice`: Lo que eligió el vecino al entrar con Google por primera vez.
- `Future<NeighborhoodChoice?> askNeighborhood(BuildContext context)`: Hoja que aparece la PRIMERA vez que alguien entra con Google: falta saber a qué barrio pertenece y cómo va a usar la app.
- `Future<String?> continueWithGoogle`: Flujo completo de "Continuar con Google" desde el login o el registro. [joinCode]/[role] llegan desde el registro (ya escritos en el formulario); desde el login van null y, si la cuenta es nueva, se piden en una hoja. Devuelve null si entró (o el vecino canceló) o el mensaje de error a mostrar.
- `class AuthBackButton extends StatelessWidget`: Botón ‹ de las pantallas de cuenta: círculo blanco, sin borde, con sombra. Es el mismo en registro, código de confirmación y recuperar contraseña.
- `class UnderlinedLink extends StatelessWidget`: Enlace subrayado de abajo ("Volver a inicio de sesión", "Volver para cambiar datos"): hace obvio cómo salir de la pantalla.

#### `mi_barrio_app/lib/features/auth_barrio/presentation/widgets/auth_validators.dart`

- `class AuthValidators`: Validaciones de los formularios de cuenta, en lenguaje simple.
  - `static String? newEmail(String? value)`: Correo para CREAR una cuenta: además del formato, corta los correos que nunca recibirían el código (temporales, errores de tipeo, Gmail imposibles). El servidor repite estas reglas y además revisa el dominio.
  - `static String? newPassword(String? value)`: Contraseña NUEVA (registro o cambio): 8+ caracteres, con letras y números.
  - `static int strength(String password)`: 0 = vacía, 1 = débil, 2 = regular, 3 = buena, 4 = fuerte.

#### `mi_barrio_app/lib/features/auth_barrio/presentation/widgets/neighborhood_emergency_card.dart`

- `class NeighborhoodEmergencyCard extends StatefulWidget`: Tarjeta del administrador del barrio para activar el Modo Emergencia de TODOS. Los celulares de los vecinos lo reciben en su siguiente sincronización.

### App: Chat entre vecinos

#### `mi_barrio_app/lib/features/chat/data/chat_models.dart`

Chat entre vecinos sobre un favor o un servicio (viene del servidor).

- `enum ChatKind`: De qué se habla: un favor del muro o un servicio de un comerciante.
- `class ChatTarget`: La publicación del chat y su dueño (autor del favor o comerciante).
- `class ChatMessage`: Un mensaje del chat entre el dueño de una publicación y un vecino.
- `class ConversationSummary`: Una conversación, vista por quien consulta ([otherName] = la otra persona).

#### `mi_barrio_app/lib/features/chat/data/chat_remote_ds.dart`

- `class ChatRemoteDatasource`: Chat en el servidor (`/api/v1/chat/...`). Necesita internet.
  - `Future<List<ConversationSummary>> inbox(String tenantId) async`: "Mis mensajes": todas mis conversaciones, la más reciente primero.
  - `Future<List<ConversationSummary>> conversations`: Conversaciones de una publicación (el dueño ve todas; otro vecino, la suya).

#### `mi_barrio_app/lib/features/chat/presentation/chat_screen.dart`

- `class ChatScreen extends StatefulWidget`: Chat en tiempo real sobre un favor o un servicio, entre su dueño (autor o comerciante) y un vecino. Conversación = (publicación, vecino que no es el dueño): [neighborUserId]. Enviar = REST (queda guardado aunque el otro no esté); recibir = WebSocket.
  - `final String otherName`: Con quién se habla (dueño o vecino), para el título.

#### `mi_barrio_app/lib/features/chat/presentation/conversations_screen.dart`

- `class ConversationsScreen extends StatefulWidget`: Lista de conversaciones que se refresca sola cuando llega un mensaje. • [target] != null: las de UNA publicación (lo que ve su dueño). • [target] == null: "Mis mensajes", todas las del vecino.
- `class ConversationTile extends StatelessWidget`: Fila de una conversación: avatar, nombre, sobre qué es y el último mensaje.
  - `final bool showContext`: En "Mis mensajes" se muestra de qué publicación se habla.

### App: Modo emergencia: pedir ayuda, mapa y grupos de apoyo

#### `mi_barrio_app/lib/features/emergency_support/data/datasources/support_groups_sqlite_ds.dart`

- `class SupportGroupsSqliteDatasource`: Grupos de apoyo guardados en el teléfono (llegan en el pull de /sync). Funciona 100 % sin internet. Uso en pantalla (sección "Grupos de apoyo" en emergencia):
  - `Future<List<SupportGroupModel>> activeGroups`: Grupos activos del barrio. Con [lat]/[lng]: del más cercano al más lejano (los que no tienen ubicación van al final); sin ubicación: por nombre. [groupType] filtra por tipo (ej. `SupportGroupType.albergue`).
  - `Future<int> countActive(String tenantId) async`: Cuántos grupos activos hay (para mostrar la sección solo si hay alguno).

#### `mi_barrio_app/lib/features/emergency_support/data/models/support_group_model.dart`

Tipos de grupo de apoyo (contrato: `support_groups.group_type`).

- `class SupportGroupType`: Tipos de grupo de apoyo (contrato: `support_groups.group_type`).
- `class SupportGroupModel`: Grupo de apoyo del barrio (brigada, albergue, olla común...). Lo registra la junta en el servidor; el teléfono solo lo lee (sin internet).
  - `final double? distanceKm`: Distancia al vecino; null si el grupo no tiene ubicación o no se pidió.

#### `mi_barrio_app/lib/features/emergency_support/data/models/vulnerable_report_model.dart`

- `class VulnerableReportModel`: Conversión entre la entidad, SQLite (0/1 + sync_status) y el payload de /sync/push.
  - `static Map<String, Object?> toSyncPayload(VulnerableReport r)`: `tenant_id` viaja en el header. El servidor valida que `reporter_user_id` sea quien envía; si es otro vecino, solo acepta "voy en camino".

#### `mi_barrio_app/lib/features/emergency_support/data/repositories/emergency_repository_impl.dart`

- `class EmergencyRepositoryImpl implements EmergencyRepository`: SOS 100% offline: se guarda en SQLite (PENDING) + cola de sincronización, en una sola transacción. El SyncCoordinator lo sube apenas haya señal.
  - `Stream<void> get changes`: Cambia cuando se guarda algo aquí o cuando termina un pull (datos de otros vecinos).

#### `mi_barrio_app/lib/features/emergency_support/domain/entities/vulnerable_report_entity.dart`

Reporte de vecino en situación vulnerable (contrato `vulnerable_reports`).

Es la entidad que consume la UI. Dev 2 la llena desde SQLite / sync (ver `domain/repositories/emergency_repository.dart`).

- `class VulnerableReport`: Reporte de vecino en situación vulnerable (contrato `vulnerable_reports`). Es la entidad que consume la UI. Dev 2 la llena desde SQLite / sync (ver `domain/repositories/emergency_repository.dart`).
  - `final String urgencyLevel`: [UrgencyLevel.critica], [UrgencyLevel.alta] o [UrgencyLevel.media].
  - `final String vulnerabilityType`: Uno de [VulnerabilityType.values].
  - `final String status`: Uno de [ReportStatus.values].
  - `final String updatedAt`: ISO-8601 UTC.
  - `final bool isPending`: true si todavía no llegó al servidor (se muestra "Pendiente").
  - `final String? otherTypeLabel`: Lo que escribió el vecino si eligió "Otro" (máx. 30 caracteres).
  - `final List<String> vulnerableGroups`: Valores de [VulnerableGroup] (puede haber varios).
  - `String get typeLabel`: Qué pasa, en palabras simples (con "Otro", lo que escribió el vecino).
- `class UrgencyLevel`: Nivel de urgencia (contrato: `urgency_level`).
  - `static int rank(String level)`: Orden de prioridad: menor número = más urgente.
- `class VulnerabilityType`: Tipo de vulnerabilidad (contrato: `vulnerability_type`).
  - `static const otro`: "Otro": el vecino escribe qué pasa (máx. [maxOtherLabel] caracteres).
  - `static const labels =`: Lenguaje simple (lo entiende una niña de 10 años o una persona bajo estrés). El valor que viaja al servidor NO cambia, solo el texto.
  - `static String defaultUrgency(String type)`: Urgencia sugerida por tipo (el vecino no tiene que pensar en eso al pedir ayuda).
- `class ReportStatus`: Estado del reporte (contrato: `status`).
- `class VulnerableGroup`: Personas que necesitan más cuidado en una emergencia (contrato: `vulnerable_groups`, separados por coma).

#### `mi_barrio_app/lib/features/emergency_support/domain/neighbor_pins.dart`

- `enum PinItemKind`: Qué publicó un vecino (para el color del marcador y la lista al tocarlo).
- `class PinItem`: Una publicación dentro del marcador de su autor.
  - `final String updatedAt`: ISO-8601: la más reciente decide dónde se dibuja a la persona.
  - `final bool canOfferHelp`: SOS ajeno que todavía necesita apoyo ("Voy en camino").
- `class NeighborPin`: Un vecino en el mapa, con todas sus publicaciones activas.
  - `PinItemKind get mainKind`: El SOS manda: un vecino que pide ayuda se ve rojo aunque también ofrezca algo.
- `class NeighborPins`: Agrupa publicaciones por persona y ubica a cada una donde publicó lo último (prioriza el SOS: es lo que hay que encontrar rápido). Muchas publicaciones usan el centro del barrio como ubicación: si varias personas caen en el mismo punto, se reparten en un círculo pequeño para que todos los marcadores se puedan tocar.
  - `static const spreadDegrees`: Separación entre marcadores que coinciden (≈ 30 m).

#### `mi_barrio_app/lib/features/emergency_support/domain/repositories/emergency_repository.dart`

- `abstract class EmergencyRepository`: Contrato entre la UI de emergencia (Dev 3) y los datos (Dev 2). Dev 2 lo implementa en `data/repositories/emergency_repository_impl.dart` usando SQLite (`vulnerable_reports` + `sync_outbox`), igual que el muro: • [createSos] guarda al instante sin red (PENDING + outbox). • [activeReports] lee del teléfono. • [changes] emite cuando cambian los datos (publicación local o pull). Luego se registra con `EmergencyReports.use(EmergencyRepositoryImpl())` (ver `presentation/providers/emergency_provider.dart`).
  - `Future<List<VulnerableReport>> activeReports(String tenantId)`: Pedidos de ayuda vigentes del barrio (no borrados).
  - `Future<VulnerableReport> createSos`: Crea un SOS. Debe funcionar sin internet.
  - `Future<VulnerableReport> offerHelp`: "Voy en camino": el vecino [helperUserId] se ofrece a ayudar.
  - `Stream<void> get changes`: Avisa a las pantallas que deben recargar.

#### `mi_barrio_app/lib/features/emergency_support/presentation/providers/emergency_provider.dart`

- `class EmergencyReports`: Punto único donde la UI de emergencia obtiene sus datos. Mientras Dev 2 termina la tabla local `vulnerable_reports`, se usa [InMemoryEmergencyRepository] (los SOS viven mientras la app está abierta). Para conectar SQLite + sync basta una línea en `main.dart`: `EmergencyReports.use(EmergencyRepositoryImpl());`
  - `static bool get isTemporary`: true mientras se usa el repositorio temporal en memoria.
- `class HelpLocation`: Ubicación usada para ordenar por cercanía y para el SOS.
  - `final bool fromGps`: false = se usó el centro del barrio porque el GPS no respondió.
- `typedef HelpLocationResolver`: Cómo se obtiene la ubicación para pedir ayuda (reemplazable en pruebas).
- `class HelpLocator`: Obtiene la ubicación del GPS y, si falla (permiso, apagado, demora), usa el centro del barrio: la app nunca se queda sin poder pedir ayuda.
- `class InMemoryEmergencyRepository implements EmergencyRepository`: Implementación temporal en memoria (también se usa en los tests).

#### `mi_barrio_app/lib/features/emergency_support/presentation/screens/emergency_map_screen.dart`

- `class EmergencyMapScreen extends StatefulWidget`: Pestaña "Mapa". • **Mapa** (por defecto): cada vecino que publicó, con sus pedidos de ayuda, favores y servicios ([NeighborMap]). • **Lista**: los pedidos de ayuda, por cercanía ("Más cerca") o por urgencia ("Más urgente"), y debajo los favores y servicios (lo mismo que el mapa).
  - `final bool startInList`: true = abre directamente en la vista de lista.

#### `mi_barrio_app/lib/features/emergency_support/presentation/screens/humanitarian_board_screen.dart`

- `class HumanitarianBoardScreen extends StatefulWidget`: Tablero de ayuda humanitaria. • [sortByDistance] = false: por urgencia (Crítica → Alta → Media) y, dentro de cada nivel, primero los que aún necesitan apoyo y los más recientes. • [sortByDistance] = true: del más cercano al más lejano (Mapa en modo lista).
  - `final Widget? header`: Contenido opcional arriba de la lista (lo usa el Mapa).
  - `final Widget? footer`: Contenido opcional debajo de los pedidos de ayuda (en el Mapa: los favores y servicios, para que la lista muestre lo mismo que el mapa).

#### `mi_barrio_app/lib/features/emergency_support/presentation/widgets/help_report_card.dart`

- `class HelpReportCard extends StatelessWidget`: Tarjeta de un pedido de ayuda. La urgencia se comunica con franja de color + ícono + texto (nunca solo color).

#### `mi_barrio_app/lib/features/emergency_support/presentation/widgets/nearby_posts_list.dart`

- `class NearbyPostsList extends StatefulWidget`: Lista del Mapa: los mismos favores y servicios que se ven en el mapa (antes la lista solo mostraba pedidos de ayuda y casi siempre salía vacía). Funciona sin internet: lee el teléfono.

#### `mi_barrio_app/lib/features/emergency_support/presentation/widgets/neighbor_map.dart`

- `class NeighborMap extends StatefulWidget`: Mapa del barrio: un marcador por vecino con sus publicaciones activas (pedidos de ayuda, favores y servicios). Al tocarlo, se ven todas. Los datos salen del teléfono (funciona sin internet). Las calles del fondo (OpenStreetMap) solo se ven con conexión; sin ella quedan los marcadores sobre un fondo liso.
  - `final bool? showStreets`: Calles de OpenStreetMap (por defecto sí, salvo en los tests: sin red).

#### `mi_barrio_app/lib/features/emergency_support/presentation/widgets/sos_sheet.dart`

- `Future<bool> showSosSheet(BuildContext context) async`: Abre el flujo SOS (Clic 1 = botón "Ayuda"). Devuelve true si se guardó el pedido.
- `class SosSheet extends StatefulWidget`: Hoja "Pedir ayuda": • Clic 2: elegir qué pasa (tarjetas grandes con ícono y texto). • Clic 3: "Enviar pedido de ayuda" (siempre a la vista, abajo). La urgencia se sugiere sola según el tipo. Los datos de la urgencia (personas, heridos, quiénes necesitan más cuidado, teléfono) son opcionales.
  - `static const savedWithoutGps`: Valor con el que se cierra la hoja si se guardó sin la ubicación del GPS.

### App: Documentos legales dentro de la app

#### `mi_barrio_app/lib/features/legal/legal_documents.dart`

- `class LegalDocument`: Documentos legales y de ayuda que se ven dentro de la app. Los .md viven en `assets/legal/` y son copia de `docs/legal/` y `docs/manual_de_usuario.md`: si se cambia un documento, copiarlo también aquí.
  - `final String file`: Nombre del archivo (también se usa para abrir enlaces entre documentos).
  - `static const all`: Orden en la pantalla "Términos y privacidad".
  - `static LegalDocument? fromLink(String link)`: Documento al que apunta un enlace como `politica_de_uso.md` o `legal/politica_de_uso.md`. null si no es uno de los nuestros.

#### `mi_barrio_app/lib/features/legal/legal_screens.dart`

- `Future<void> openLegalDocument(BuildContext context, LegalDocument doc)`: Abre un documento (no necesita sesión: se usa también en el registro).
- `class LegalDocumentsScreen extends StatelessWidget`: Lista "Términos y privacidad" (desde la pestaña "Tú").
- `class LegalDocumentScreen extends StatelessWidget`: Un documento, leído de los assets de la app (funciona sin internet).
  - `final AssetBundle? bundle`: Reemplazable en pruebas.
- `class LegalConsentText extends StatefulWidget`: "Al crear tu cuenta aceptas los Términos y la Política de privacidad." Con enlaces que abren cada documento. Se muestra en registro y login.

#### `mi_barrio_app/lib/features/legal/markdown_view.dart`

- `class MarkdownView extends StatelessWidget`: Muestra un Markdown sencillo (el de nuestros documentos) sin librerías extra. Soporta: títulos (#, ##, ###), párrafos, listas (- y 1.), citas (>), tablas (| a | b |), líneas (---), **negrita**, `código` y [enlaces](destino).
  - `final void Function(String target) onLink`: Se llama al tocar un enlace con su destino (p. ej. "politica_de_uso.md").
- `enum MdKind`: Tipos de bloque que entiende [MarkdownView].
- `class MdBlock`: Un bloque del documento: título, párrafo, lista, cita, tabla o línea.
- `List<MdBlock> parseMarkdown(String source)`: Convierte el texto en bloques. Público para poder probarlo.
- `List<InlineSpan> inlineSpans`: Texto con **negrita**, `código` y [enlaces](destino).

### App: Moderación: reportes y cuentas suspendidas

#### `mi_barrio_app/lib/features/moderation/data/content_reports.dart`

- `class ReportTarget`: Qué se reporta (contrato: `target_type`).
- `class ReportReason`: Motivos del reporte (contrato: `reason`), en el orden en que se muestran.
- `class ContentReportsDatasource`: Reportes del vecino: se guardan en el teléfono y se suben por el sync, así funcionan sin internet. Lo reportado deja de verse para quien reporta.
  - `Future<void> report`: Guarda el reporte (PENDING) y lo encola. Lanza [ArgumentError] si falta el motivo escrito de "Otro".
- `class ReportedItem`: Publicación reportada, tal como la ve el administrador.
- `class ModerationRemoteDatasource`: Panel de reportes: administrador del barrio ([tenantId]) o superadministrador (sin barrio: ve todos).
  - `final String? tenantId`: null = superadministrador (todos los barrios).
  - `Future<void> resolve(ReportedItem item, String action) async`: [action]: `restore` (vuelve a mostrarse) o `remove` (se elimina).

#### `mi_barrio_app/lib/features/moderation/data/suspended_accounts.dart`

- `class SuspendedAccount`: Vecino suspendido por reportes (3 vecinos distintos reportaron sus publicaciones). Solo el jefe del barrio lo puede reactivar.
- `class SuspendedAccountsDatasource`: Panel del jefe del barrio: lista las cuentas suspendidas por reportes y las reactiva.

#### `mi_barrio_app/lib/features/moderation/presentation/report_flow.dart`

- `class ReportButton extends StatelessWidget`: Botón 🚩 "Reportar" para el detalle de un favor o un servicio.
  - `final VoidCallback? onReported`: Se llama después de enviar el reporte (p. ej. para cerrar el detalle: quien reporta deja de ver la publicación).
- `Future<bool> showReportFlow`: Flujo de reporte: motivo → confirmación → listo. Cada modal se cierra antes de abrir el siguiente (nunca quedan uno encima de otro). Devuelve true si el reporte se guardó.

#### `mi_barrio_app/lib/features/moderation/presentation/reports_panel.dart`

- `class ReportsPanelCard extends StatefulWidget`: Panel "Reportes" para el administrador del barrio ([tenantId]) o el superadministrador (sin [tenantId]: todos los barrios). Con 3 reportes de vecinos distintos la publicación ya está oculta ("En revisión"); aquí se decide si vuelve a mostrarse o se elimina.

#### `mi_barrio_app/lib/features/moderation/presentation/suspended_accounts_card.dart`

- `class SuspendedAccountsCard extends StatefulWidget`: Para el jefe del barrio: vecinos suspendidos por reportes y el botón para reactivarlos después de hablar con ellos.

### App: Tutorial de bienvenida

#### `mi_barrio_app/lib/features/onboarding_tutorial/presentation/screens/tutorial_gate.dart`

- `class TutorialGate extends StatefulWidget`: Muestra el tutorial la primera vez que una cuenta entra; después, [child]. La bandera la maneja [TutorialProgress] (Dev 2): queda en el teléfono al instante y se sincroniza con el perfil, así no se repite ni en otro teléfono.

#### `mi_barrio_app/lib/features/onboarding_tutorial/presentation/screens/tutorial_screen.dart`

- `class TutorialScreen extends StatefulWidget`: Tutorial de bienvenida: 3 pasos, se muestra solo la primera vez. "Saltar" y "Empezar" llaman a [onFinished]; quien lo muestra guarda que ya se vio.

#### `mi_barrio_app/lib/features/onboarding_tutorial/presentation/widgets/tutorial_step_card.dart`

- `class TutorialStepCard extends StatelessWidget`: Un paso del tutorial: ícono grande, título y explicación corta.

### App: Pestaña Tú: perfil, historial y cuenta

#### `mi_barrio_app/lib/features/profile_me/data/profile_local_storage.dart`

- `class ProfileLocalStorage`: Guarda y lee el perfil del vecino en SQLite ("Mi Perfil y Cuenta"). "Guardar cambios" escribe con `PENDING` y encola un UPSERT para el sync.
  - `Future<UserProfileModel> updatePhoto`: Cambia SOLO la foto de perfil; todo lo demás se conserva tal cual. Lanza [StateError] si todavía no hay perfil guardado.
  - `Future<UserProfileModel> saveProfile`: Guarda el perfil (crear o editar). Lanza [ArgumentError] si hay datos inválidos.

#### `mi_barrio_app/lib/features/profile_me/data/profile_sync.dart`

- `class ProfileSync`: Mantiene la fila `users` del propio vecino al día con el servidor. Sin esto la app no sabía el ROL real (un COMERCIANTE no veía "Ofrecer servicio") ni el nombre en "Tú", ni si ya vio el tutorial en otro teléfono. • [seedFromLogin]: sin red, con lo que devolvió el login. • [refreshFromServer]: `GET /api/v1/users/me` (perfil completo). Nunca pisa cambios del perfil hechos sin internet (PENDING / FAILED): en ese caso solo actualiza el rol (lo decide el servidor) y la bandera del tutorial (si alguno de los dos dice "visto", queda visto).
  - `Future<void> seedFromLogin`: Crea o corrige la fila local con los datos del login (rol, nombre, barrio). [role] es el valor del contrato: VECINO, COMERCIANTE, ADMIN_BARRIO.
  - `Future<UserProfileModel?> refreshFromServer`: Trae el perfil completo del servidor. Devuelve el perfil guardado o null si no hay red / el servidor falló (la app sigue con lo local).

#### `mi_barrio_app/lib/features/profile_me/data/tutorial_progress.dart`

- `class TutorialProgress`: "¿Ya vio el tutorial?" por vecino. El tutorial se muestra solo la primera vez. Se guarda en 2 lugares: • `app_settings` (`tutorial_completed:<userId>`): respuesta inmediata y sin red; sobrevive al cierre de sesión (se borra la fila `users`, no esto). • `users.tutorial_completed` + cola de sync: llega al servidor, así en un teléfono nuevo tampoco se repite (lo trae [ProfileSync]). Uso en pantalla:
  - `Future<bool> isCompleted(String userId) async`: true si este vecino ya terminó (o saltó) el tutorial en este teléfono o en otro (dato que bajó del servidor).
  - `Future<void> markCompleted`: Marca el tutorial como visto. Funciona sin internet: queda en el teléfono al instante y se envía al servidor en el próximo sync. Llamarlo 2 veces no encola nada nuevo.
  - `Future<void> queueServerUpdate`: Envía SOLO la bandera al servidor (update parcial: el servidor cambia únicamente los campos que llegan, así no se pisa el teléfono ni el nombre).
  - `Future<bool> localFlag(String userId) async`: Solo la bandera local (sin mirar el perfil).
  - `Future<void> rememberLocally(DatabaseExecutor executor, String userId)`: Guarda la bandera local sin encolar nada (cuando ya viene del servidor).
  - `static Future<bool> localFlagIn(DatabaseExecutor executor, String userId)`: Igual que [localFlag], pero dentro de una transacción ya abierta (sqflite se bloquea si se consulta la base fuera de la transacción).

#### `mi_barrio_app/lib/features/profile_me/data/user_profile_model.dart`

- `class UserRole`: Roles del vecino (contrato: `users.role`), con etiqueta legible.
- `class PublisherType`: Tipo de publicador (v3, "Perfil de publicador").
- `class UserProfileModel`: Perfil del vecino (tabla `users`).
  - `final String? emailContacto`: Correo para que los vecinos te contacten (distinto del correo de la cuenta).
  - `String get initials`: Iniciales para el avatar cuando no hay foto ("María López" → "ML").
  - `Map<String, Object?> toSyncPayload()`: Payload para `/sync/push`. El rol NO viaja: no se puede auto-asignar "Líder vecinal" desde el teléfono.

#### `mi_barrio_app/lib/features/profile_me/presentation/screens/edit_profile_screen.dart`

- `class EditProfileScreen extends StatefulWidget`: "Mi Perfil y Cuenta": datos personales, redes de contacto y perfil de publicador. Guarda en SQLite con `PENDING` y encola el cambio; el SyncWorker lo sube cuando hay internet. "Guardar cambios" se habilita solo cuando algo cambió.

#### `mi_barrio_app/lib/features/profile_me/presentation/screens/history_screen.dart`

- `class HistoryScreen extends StatefulWidget`: "Mi historial": lo que publicó el vecino, en 3 pestañas con contador. Se lee solo del teléfono (funciona sin internet); cada ítem lleva su chip de sync.

#### `mi_barrio_app/lib/features/profile_me/presentation/screens/profile_screen.dart`

- `class ProfileScreen extends ConsumerStatefulWidget`: Pestaña "Tú": quién soy, mi actividad y accesos rápidos. Los datos se ven aquí en modo lectura; se editan en un solo lugar ("Editar perfil"). La foto se cambia tocando la cámara del avatar.

### App: Servicios del barrio

#### `mi_barrio_app/lib/features/proximity_services/data/datasources/endorsements_sqlite_ds.dart`

- `class EndorsementsSqliteDatasource`: Calificaciones con estrellas, 100% offline.
  - `Future<EndorsementModel> rateService`: Crea o edita la calificación del vecino para un servicio (upsert). • [rating] 1 a 5, o null para dejar las estrellas vacías. • [shortComment] opcional, máximo 140 caracteres. • [photoB64] opcional (JPEG comprimido). Lanza [ArgumentError] si los datos son inválidos, si el servicio no existe en el barrio o si el vecino intenta calificar su propio servicio.
  - `Future<EndorsementModel> removeEndorsement`: Retira el visto bueno localmente y encola la eliminación lógica para sincronizarla con el servidor.
  - `Future<EndorsementModel?> myRating`: La calificación de este vecino para el servicio (null si aún no calificó).
  - `Future<Map<String, EndorsementModel>> myRatings`: Mis calificaciones de varios servicios en UNA consulta (antes era una por servicio y la lista tardaba más cuantos más servicios había).
  - `Future<List<EndorsementModel>> listForService`: Calificaciones del servicio guardadas en el teléfono, las más recientes primero.

#### `mi_barrio_app/lib/features/proximity_services/data/datasources/merchant_business_remote_ds.dart`

- `class MerchantBusinessRemoteDatasource`: Llamadas del comerciante al servidor: reseñas de sus servicios y sus respuestas.

#### `mi_barrio_app/lib/features/proximity_services/data/datasources/services_remote_ds.dart`

- `class ServiceReviews`: Lista de calificaciones de un servicio lista para la hoja de detalle.
  - `final List<EndorsementModel> items`: Más recientes primero. Las calificaciones mías aún sin subir (PENDING) aparecen con su estado local, aunque el servidor tenga una versión vieja.
  - `final bool fromServer`: false = sin internet (o el servidor falló): se muestra lo guardado en el teléfono.
  - `final Set<String> withPhoto`: Ids de calificaciones que tienen foto (se pide aparte con [ServicesRemoteDatasource.fetchEndorsementPhoto]).
  - `final bool photoFlagsKnown`: false = el servidor no dice qué calificaciones tienen foto (no manda `has_photo`): la pantalla puede pedir la foto al abrir cada una y [ServicesRemoteDatasource.fetchEndorsementPhoto] devuelve null si no hay.
  - `double? get average`: Promedio de lo que se ve en la lista (null si nadie puso estrellas).
- `class ServicesRemoteDatasource`: Lecturas del servidor para el directorio de oficios. Contrato con el backend (Dev 1, Sprint 10): • `GET /api/v1/services/{id}/endorsements` → lista (o `{"items": [...]}`) de `{id, service_id, endorser_user_id, rating, short_comment, has_photo, updated_at}`. **Sin** `photo_b64`, para que la lista pese poco. • `GET /api/v1/endorsements/{id}/photo` → `{"photo_b64": "..."}`. Si no hay red o el endpoint aún no existe (404), cae a SQLite: la app nunca muestra un error por esto.
  - `Future<ServiceReviews> fetchEndorsements`: Calificaciones del servicio: del servidor si hay red (y se guardan en SQLite para verlas luego sin red); si no, las del teléfono.
  - `Future<List<String>> fetchServicePhotos`: Fotos de un servicio (base64). Vacío si no tiene o no hay red.
  - `Future<String?> fetchEndorsementPhoto`: Foto de una calificación (base64) o null si no tiene / no hay red.

#### `mi_barrio_app/lib/features/proximity_services/data/datasources/services_sqlite_ds.dart`

- `class ServicesSqliteDatasource`: Acceso offline al directorio de oficios. Funciona 100% sin internet.
  - `Future<LocalServiceModel> insertService`: Registra un oficio al instante con `sync_status = 'PENDING'` y lo encola para sincronizar, en una sola transacción. Lanza [ArgumentError] si algún dato es inválido (no se guarda nada).
  - `Future<LocalServiceModel> updateService`: Edita un servicio PROPIO ya publicado. Funciona sin internet (PENDING). [photos] null = no se tocan las fotos; una lista = reemplaza las fotos.
  - `Future<void> retireService`: "Retirar servicio": deja de verse en el barrio (borrado lógico, se sincroniza).
  - `Future<List<String>> localPhotos(String serviceId) async`: Fotos guardadas en el teléfono (vacío si aún no se descargaron).
  - `Future<void> cachePhotos`: Guarda las fotos descargadas para verlas luego sin internet.
  - `static const maxPhotoB64Length`: Tope por foto (JPEG comprimido en base64), menor que el del servidor.
  - `Future<List<LocalServiceModel>> getServices`: Oficios locales del barrio, ordenados por cantidad de recomendaciones.

#### `mi_barrio_app/lib/features/proximity_services/data/models/endorsement_model.dart`

- `class EndorsementModel`: Calificación con estrellas de un servicio (`neighbor_endorsements`).
  - `static const maxPhotoB64Length`: Foto JPEG comprimida (~480 px) en base64: tope de seguridad ~80 KB.
  - `static String idFor(String serviceId, String endorserUserId)`: Id determinístico: la misma persona calificando el mismo servicio genera SIEMPRE el mismo id, en cualquier teléfono. Así el upsert funciona y el UNIQUE(service_id, endorser_user_id) del backend nunca rompe el lote de sincronización.
  - `final int? rating`: 1 a 5, o null si el vecino dejó las estrellas vacías.
  - `final String? endorserName`: Nombre público de quien calificó ("Rosa C."); lo manda el servidor.

#### `mi_barrio_app/lib/features/proximity_services/data/models/service_model.dart`

- `class ServiceCategory`: Categorías de oficios (contrato: `category`), con etiqueta para la UI.
  - `static const labels =`: En el orden en que se muestran (los más pedidos primero; "Otros" al final).
- `class LocalServiceModel`: Oficio del directorio vecinal (`local_services`).
  - `final int endorsementsCount`: Lo calcula el servidor a partir de `neighbor_endorsements`; el teléfono solo lo muestra.
  - `final double? ratingAvg`: Promedio de estrellas (1 a 5) calculado por el servidor; null = sin calificaciones.
  - `final String? publisherType`: Perfil de publicador (v3): Persona natural, Emprendedor, Bodega, etc.
  - `final String? contactPhone`: Contacto del comerciante (teléfono / WhatsApp). Lo manda el servidor en el pull; el teléfono no lo envía (no viaja en [toSyncPayload]).
  - `final String? priceText`: Precio en texto libre ("S/ 30 la visita", "A tratar"); null = sin precio.
  - `final int photoCount`: Cuántas fotos tiene (se descargan aparte, ver `service_photos`).
  - `static const maxPhotos`: Hasta 4 fotos por servicio (mismo tope que el servidor).
  - `final String flowType`: Ofrezco (`OFREZCO_AYUDA`) o Necesito (`SOLICITO_AYUDA`): mismos valores que el muro de Apoyo.
  - `final bool isUnderReview`: 3 vecinos lo reportaron: oculto hasta que el administrador lo revise.
  - `final String? providerRole`: Rol de quien publica (`VECINO` / `COMERCIANTE`), para la insignia.
  - `Map<String, Object?> toSyncPayload()`: Payload para `/sync/push`. No incluye `endorsements_count` ni `rating_avg`: los calcula el servidor (si dos teléfonos los enviaran, LWW perdería votos).

#### `mi_barrio_app/lib/features/proximity_services/presentation/screens/merchant_business_screen.dart`

- `class MerchantBusinessScreen extends StatefulWidget`: "Mi negocio": mis servicios (desde el teléfono, sin internet) con accesos a editar, ver mensajes de clientes y responder sus reseñas (con internet).

#### `mi_barrio_app/lib/features/proximity_services/presentation/screens/services_directory_screen.dart`

- `class ServicesDirectoryScreen extends StatefulWidget`: Pestaña Servicios: buscar, filtrar y ver los servicios del barrio (funciona sin internet).

#### `mi_barrio_app/lib/features/proximity_services/presentation/widgets/offer_service_sheet.dart`

- `class MerchantProfile`: Lo que la app necesita saber del vecino para ofrecer un servicio.
- `Future<MerchantProfile> loadMerchantProfile`: Lee el rol y el perfil de publicador del vecino desde su perfil local (tabla `users`). Si no hay perfil guardado, no es comerciante.
- `Future<bool> showOfferServiceSheet`: Abre "Ofrecer servicio" (o "Editar servicio" si viene [existing]) en pantalla completa. Devuelve true si se guardó.
- `class OfferServiceSheet extends StatefulWidget`: Formulario de servicio: rubro, qué ofreces, precio, fotos, dónde atiendes y si atiendes emergencias. Para crear o editar ([existing]). Se guarda al instante en el teléfono (PENDING) aunque no haya internet.
  - `final String initialFlowType`: Con qué opción abre: Pedir (por defecto, como en Apoyo) o Brindar.
  - `final LocalServiceModel? existing`: Servicio a editar (null = nuevo).
  - `final double? lat`: Ubicación inicial (por defecto: GPS o, si no hay, el centro del barrio).

#### `mi_barrio_app/lib/features/proximity_services/presentation/widgets/service_card.dart`

- `class ServiceCard extends StatelessWidget`: Tarjeta de un servicio en la lista: título, rubro, precio, calificación, vistos buenos y fotos.
  - `final bool isNeed`: true = es un pedido ("Pedir"): no lleva estrellas ni Visto Bueno.
  - `final String? publisherBadge`: "Vecino" o "Negocio": quién lo publica.
  - `final bool isUnderReview`: Propio y oculto por reportes, hasta que el administrador lo revise.
  - `final double? ratingAvg`: Promedio de estrellas (null = sin calificaciones con estrellas).
  - `final bool isOwn`: true = es un servicio del propio vecino.
  - `final String? priceText`: "S/ 30 la visita" (null = sin precio publicado).

#### `mi_barrio_app/lib/features/proximity_services/presentation/widgets/service_category_ui.dart`

- `class ServiceCategoryUi`: Ícono y etiqueta corta de cada categoría de oficio (un solo lugar para el directorio, el detalle y "Ofrecer servicio").

#### `mi_barrio_app/lib/features/proximity_services/presentation/widgets/service_detail_sheet.dart`

- `Future<void> showServiceDetailSheet`: Abre el detalle de un servicio en una hoja inferior.
- `class ServiceDetailSheet extends StatefulWidget`: Detalle del servicio: mini mapa sin internet, contacto, calificaciones de vecinos y formulario "Califica este servicio" (estrellas + comentario).
  - `final ChatRemoteDatasource? chatRemote`: Chat con el comerciante (los tests pasan uno falso).
  - `final ServicesRemoteDatasource? remoteDatasource`: Calificaciones del servidor. Si es null se usa el real (salvo en tests).
  - `final double? centerLat`: Centro del barrio para el mini mapa (por defecto, el de la sesión).
  - `final ValueListenable<SyncPhase>? syncPhase`: Solo para pruebas: reemplaza al estado global de sincronización.

#### `mi_barrio_app/lib/features/proximity_services/presentation/widgets/visto_bueno_badge.dart`

- `class VistoBuenoBadge extends StatefulWidget`: Botón "Visto bueno" con contador y una pequeña animación al tocarlo.

### App: Apoyo: muro de favores

#### `mi_barrio_app/lib/features/solidarity_network/data/datasources/solidarity_remote_ds.dart`

- `class SolidarityRemoteDatasource`: Lo que del favor vive en el servidor y necesita internet: la foto, los comentarios y las reseñas (el chat está en `features/chat`).
  - `Future<List<String>> fetchPhotos(String tenantId, String postId) async`: Todas las fotos del favor (hasta 4). Si el servidor aún no tiene la ruta nueva, usa la de una sola foto. Vacío si no tiene o no hay red.
  - `Future<String?> fetchPhoto(String tenantId, String postId) async`: Foto del favor en base64, o null si no tiene / no hay red.

#### `mi_barrio_app/lib/features/solidarity_network/data/datasources/solidarity_sqlite_ds.dart`

- `class SolidaritySqliteDatasource`: Acceso offline al muro solidario. Funciona 100% sin internet.
  - `static const maxPhotoB64Length`: Tope de la foto (JPEG comprimido en base64), igual que las calificaciones.
  - `static const maxPhotos`: Fotos por favor (igual que los servicios).
  - `Future<SolidarityPostModel> publishInThreeClicks`: Guarda una publicación al instante (Clic 3: "Publicar Ahora"). • Genera el UUID v4 en el teléfono. • Guarda la fila con `sync_status = 'PENDING'`. • Encola la mutación UPSERT en `sync_outbox`. Ambas escrituras van en una sola transacción. Lanza [ArgumentError] si algún dato es inválido (no se guarda nada).
  - `Future<List<String>> localPhotos(String postId) async`: Fotos del favor guardadas en el teléfono, en orden (vacío si aún no se descargaron).
  - `Future<String?> localPhoto(String postId) async`: Primera foto (compatibilidad).
  - `Future<void> cachePhotos(String tenantId, String postId, List<String> photos) async`: Guarda las fotos descargadas para verlas luego sin internet.
  - `Future<void> cachePhoto(String tenantId, String postId, String photoB64)`: Compatibilidad: guarda una sola foto.
  - `Future<List<SolidarityPostModel>> getActivePosts`: Publicaciones activas del barrio, de la más reciente a la más antigua. [includeCompleted] = false oculta los favores COMPLETADO (el muro).
  - `Future<SolidarityPostModel?> getPost(String tenantId, String postId) async`: Un favor del barrio por id (null si no existe o fue borrado).
  - `Future<SolidarityPostModel> changeMyPostStatus`: El autor cambia el estado de SU favor (DISPONIBLE / EN_COORDINACION / COMPLETADO). Funciona sin internet: queda PENDING y entra a la cola. Lanza [ArgumentError] si el favor no existe, no es suyo o el estado no es válido. Si el estado ya es ese, no encola nada.
  - `Future<SolidarityPostModel> coordinatePost`: Otro vecino toma un favor ajeno: DISPONIBLE → EN_COORDINACION. Sin internet queda PENDING y sube al reconectar. Contrato con el backend (igual que "Voy en camino" del SOS): el payload es el favor completo con su `author_user_id` ORIGINAL y `status = EN_COORDINACION`; el servidor ve que quien envía no es el autor y solo acepta ese cambio de estado. Lanza [ArgumentError] si el favor no existe o es propio, y [StateError] si ya alguien lo coordina o está COMPLETADO.
  - `Future<int> countPending(String tenantId) async`: Cuántas publicaciones del barrio aún no llegan al servidor.

#### `mi_barrio_app/lib/features/solidarity_network/data/models/favor_interactions.dart`

Comentarios, reseñas y chat de un favor (vienen del servidor).

- `class PostComment`: Un comentario público de un favor.
- `class FavorReview`: Calificación entre vecinos al terminar un favor (1 a 5 estrellas).

#### `mi_barrio_app/lib/features/solidarity_network/data/models/solidarity_post_model.dart`

- `class SolidarityFlowType`: Tipos de flujo (contrato: `flow_type`).
- `class SolidarityModality`: Modalidades (contrato: `modality`), con etiqueta en español para la UI.
  - `static const otro`: "Otro": no se escribe una categoría nueva; el detalle va en la descripción.
  - `static const labels =`: En el orden en que se muestran ("Otro" siempre al final).
- `class SolidarityStatus`: Estados de una publicación (contrato: `status`).
- `class SolidarityPostModel`: Publicación del muro solidario. Convierte entre: • SQLite (booleanos 0/1 + `sync_status`) y • el payload de `/sync/push` (booleanos true/false, sin campos locales).
  - `final String updatedAt`: ISO-8601 UTC.
  - `final String? authorName`: Nombre público del autor ("Rosa C.").
  - `final String? contactPhone`: Teléfono / WhatsApp que el autor cargó en su perfil (para coordinar).
  - `final bool hasPhoto`: true si tiene foto (se descargan aparte, ver `post_photo_list`).
  - `final String? coordinatorUserId`: Quién está ayudando (lo registra el servidor al coordinar).
  - `final bool isUnderReview`: 3 vecinos lo reportaron: oculto hasta que el administrador lo revise.
  - `final int photoCount`: Cuántas fotos tiene (hasta 4; se descargan aparte).
  - `Map<String, Object?> toSyncPayload()`: Payload para la cola outbox / `/sync/push` (formato del contrato). `tenant_id` viaja en el header `X-Tenant-ID`, no en el cuerpo.

#### `mi_barrio_app/lib/features/solidarity_network/presentation/screens/apoyo_screen.dart`

- `Future<bool> showApoyoScreen`: Abre "Pedir / Brindar apoyo" en pantalla completa (botón Publicar de la pestaña Apoyo). Devuelve true si se publicó.
- `class ApoyoScreen extends StatefulWidget`: Formulario de apoyo (favor sin dinero): igual que el de servicios pero sin precio. Pedir / Brindar, tipo, título, descripción, fotos, ubicación y el interruptor de emergencia. Se guarda en el teléfono aunque no haya internet.
  - `final double? lat`: Ubicación inicial (por defecto: GPS o, si no hay, el centro del barrio).
  - `static const icons`: Ícono de cada tipo de apoyo.

#### `mi_barrio_app/lib/features/solidarity_network/presentation/screens/collaborative_wall_screen.dart`

- `class CollaborativeWallScreen extends StatefulWidget`: Muro de favores del barrio (pido / ofrezco ayuda), con búsqueda y filtros.
  - `final bool criticalResourcesOnly`: En Modo Emergencia prioriza recursos críticos (agua, botiquín, generador).
  - `final CoordinateFavorCallback? onCoordinate`: Marca un favor ajeno como "en coordinación" (método de la capa de datos). Si es null, el botón "Coordinar" del detalle aparece desactivado.

#### `mi_barrio_app/lib/features/solidarity_network/presentation/screens/favor_detail_screen.dart`

- `typedef CoordinateFavorCallback`: Marca un favor ajeno como "en coordinación" (capa de datos: queda en el teléfono como PENDING y se encola).
- `typedef ChangeFavorStatusCallback`: El autor cambia el estado de su favor (completado / disponible otra vez).
- `class FavorDetailScreen extends StatefulWidget`: Detalle de un favor del muro, en pantalla completa: foto, datos, quién publicó y quién ayuda, cómo contactar (WhatsApp, llamada o chat en la app), comentarios y, al completarse, las reseñas.
  - `final CoordinateFavorCallback? onCoordinate`: Si es null, ayudar solo abre el contacto (sin marcar "en coordinación").

#### `mi_barrio_app/lib/features/solidarity_network/presentation/widgets/post_meta_label.dart`

- `class PostMetaLabel`: Texto corto bajo cada favor del muro: "hace 2 h · a 300 m". Cuando Dev 2 publique `TimeAgo.label` en `lib/shared/`, [timeAgo] puede delegar en él sin cambiar la pantalla.
  - `static String? timeAgo(String updatedAtIso`: "hace un momento", "hace 5 min", "hace 2 h", "ayer", "hace 3 días". Devuelve null si la fecha no se puede leer.
  - `static String distance(double km)`: "a 300 m", "a 2,4 km"; "muy cerca" a menos de 50 m.
  - `static String? build`: Une ambos con " · ". Si falta un dato, muestra solo el otro.

#### `mi_barrio_app/lib/features/solidarity_network/presentation/widgets/support_groups_section.dart`

- `class SupportGroupsSection extends StatefulWidget`: "Grupos de apoyo" del barrio (se muestra en Apoyo durante la emergencia). Lee del teléfono, así que funciona sin señal; ordena del más cercano al más lejano.

---

## Backend (FastAPI)

### Backend: Arranque de la API

#### `mi_barrio_backend/app/main.py`

Punto de entrada de la API FastAPI: middlewares, routers, salud y manejo de errores.

- `liveness_check` · **GET /health/live**: Liveness probe that does not wake the external PostgreSQL database.
- `health_check` · **GET /health**: Comprueba de verdad la base de datos y si faltan migraciones.

### Backend: Núcleo (core): seguridad, base de datos, correo, Google y errores

#### `mi_barrio_backend/app/core/auth_security.py`

Contraseñas (PBKDF2) y tokens de sesión (JWT HS256 firmado con MI_BARRIO_JWT_SECRET).

- `hash_password`: Huella PBKDF2-SHA256 con sal aleatoria: "pbkdf2_sha256$iteraciones$sal$huella". Nunca se guarda la contraseña.
- `verify_password`: True si la contraseña coincide con la huella guardada. Compara en tiempo constante; sin huella (cuenta de Google) siempre False.
- `create_access_token`: Crea el token de sesión (JWT HS256) con el usuario, su barrio y su rol. Vence en ACCESS_TOKEN_SECONDS (24 h).
- `decode_access_token`: Valida la firma y el vencimiento del token y devuelve sus datos (claims). Lanza 401 si es falso, está alterado o venció.

#### `mi_barrio_backend/app/core/content_filter.py`

Censura de groserías y discurso de odio en lo que escriben los vecinos.

Se aplica en el servidor ANTES de guardar (sync y rutas REST), así nada ofensivo llega a otros vecinos aunque venga de una app vieja. La app usa la MISMA lista para avisar mientras se escribe.

Las palabras se cambian por su primera letra y asteriscos ("p***"). Nunca se rechaza el envío: un pedido de ayuda en una emergencia se guarda siempre.

La lista vive en offensive_words.json (junto a este archivo). La app tiene una copia idéntica en assets/moderation/; una prueba de la app falla si difieren, así que al cambiar una hay que copiarla a la otra.

- `normalize`: minúsculas, sin tildes, 4→a…, letras repetidas juntas ("puuuta" → "puta").
- `censor`: Devuelve el texto con las palabras ofensivas cambiadas por asteriscos.
- `is_offensive`: True si el texto tiene groserías o discurso de odio (si censor() lo cambiaría).
- `censor_payload`: Copia del payload de sync con los campos de texto libre censurados.

#### `mi_barrio_backend/app/core/database.py`

Conexión asíncrona a PostgreSQL (SQLAlchemy) y sesión por petición.

- `Base`: Clase base de todos los modelos SQLAlchemy (tablas) del proyecto.
- `get_db_session`: Dependencia de FastAPI: abre una sesión de base de datos por petición y la cierra al terminar.

#### `mi_barrio_backend/app/core/database_url.py`

Normaliza DATABASE_URL (Render/Neon) al formato que usa asyncpg.

- `normalize_database_url`: Convert provider PostgreSQL URLs to SQLAlchemy's asyncpg URL format.

#### `mi_barrio_backend/app/core/email_sender.py`

Envío de correos (códigos de verificación y de recuperar contraseña).

Usa SMTP. Con Gmail: una cuenta del equipo y una "contraseña de aplicación" (Cuenta de Google → Seguridad → Verificación en 2 pasos → Contraseñas de aplicaciones).

Variables de entorno (en Render → Environment): SMTP_USER correo que envía, p. ej. mibarrio.app@gmail.com SMTP_PASSWORD la contraseña de aplicación de 16 letras (sin espacios) SMTP_HOST por defecto smtp.gmail.com SMTP_PORT por defecto 587 (STARTTLS) SMTP_FROM_NAME por defecto "Mi Barrio"

Render (plan gratis) BLOQUEA el SMTP ("Network is unreachable"). Por eso, si existe BREVO_API_KEY, se envía por la API HTTPS de Brevo (gratis, 300 correos/día): BREVO_API_KEY la clave de API de Brevo (SMTP & API → API Keys) BREVO_SENDER_EMAIL remitente verificado en Brevo (por defecto SMTP_USER)

Si no hay ni Brevo ni SMTP, el correo NO se envía: el código se escribe en los logs del servidor (útil en desarrollo) y la función devuelve False.

- `is_configured`: True si hay forma de enviar correos: Brevo (BREVO_API_KEY) o SMTP (SMTP_USER y SMTP_PASSWORD).
- `send_email`: True si se envió. Nunca lanza: un correo caído no debe romper el registro.
- `send_verification_code`: Envía el código de 6 números para confirmar el correo. Si no se pudo enviar, deja el código en los logs y devuelve False.
- `send_password_reset_code`: Envía el código de 6 números para cambiar la contraseña. Si no se pudo enviar, deja el código en los logs y devuelve False.

#### `mi_barrio_backend/app/core/email_validation.py`

Filtra correos falsos ANTES de crear la cuenta.

La prueba definitiva de que un correo es real y de la persona es el código de 6 números que le llega (la cuenta no se puede usar hasta confirmarlo). Esto corta antes los casos que nunca van a recibir ese código: • correos desechables (mailinator, yopmail, 10minutemail…), • errores de tipeo comunes (gmial.com, hotmal.com…), con sugerencia, • Gmail con un usuario que Gmail no permite (muy corto, símbolos raros…), • dominios que no existen o no reciben correo (se consulta el DNS).

La consulta DNS usa DNS sobre HTTPS de Google (sin dependencias extra). Si el DNS no responde, se deja pasar: el código por correo sigue siendo el filtro.

Variables de entorno: EMAIL_DOMAIN_CHECK=0 apaga la consulta DNS (pruebas locales con dominios .test). También se apaga con AUTH_DEBUG_CODES=1.

- `check_format`: Reglas sin red. Lanza 422 con un mensaje para el vecino.
- `check_domain`: Rechaza (422) correos de dominios que no existen o no reciben correo. Los proveedores conocidos (Gmail, Outlook…) se aceptan sin consultar DNS.
- `ensure_real_email`: Formato + dominio. Úsalo antes de crear una cuenta con correo y contraseña.

#### `mi_barrio_backend/app/core/exceptions.py`

Formato común de errores de la API: {"success": false, "error": ..., "data": null}.

- `custom_http_exception_handler`: Convierte cualquier HTTPException al formato común de la API: {"success": false, "error": "...", "data": null}.
- `validation_exception_handler`: Errores de validación (422) en el formato común, con un mensaje simple y el detalle por campo.
- `unhandled_exception_handler`: Error inesperado (500): se registra completo en los logs del servidor. Al vecino le llega un mensaje simple. El detalle técnico (tipo de error, SQL) y la pista de qué revisar solo se envían fuera de producción: en producción revelarían cómo está hecha la base de datos y la app los mostraría tal cual.

#### `mi_barrio_backend/app/core/google_auth.py`

Verificación del "ID token" que entrega Google Sign-In en el celular.

El celular inicia sesión con Google y manda al servidor un ID token (un JWT firmado por Google). Aquí se valida con el endpoint oficial `tokeninfo` de Google (sin dependencias extra) y se comprueba: • que el token es para NUESTRA app (`aud` = el Web client ID del proyecto), • que lo emitió Google (`iss`), • que no venció (`exp`), • y que Google ya verificó el correo (`email_verified`).

Variable de entorno (Render → Environment): GOOGLE_CLIENT_IDS el "Web client ID" (…apps.googleusercontent.com). Puede ser una lista separada por comas.

- `GoogleIdentity`: Lo que Google confirma de la persona: su id interno (sub), su correo verificado y su nombre.
- `allowed_client_ids`: Client IDs de Google aceptados (variable GOOGLE_CLIENT_IDS, separados por comas).
- `identity_from_claims`: Valida los datos que devolvió Google. Lanza 401 si algo no cuadra.
- `verify_google_id_token`: Valida el ID token con Google (tokeninfo) y devuelve la identidad. 503 si GOOGLE_CLIENT_IDS no está configurado; 401 si el token no sirve.

#### `mi_barrio_backend/app/core/log_redaction.py`

Quita el token de sesión de los logs.

El chat en tiempo real se conecta con `?token=...` en la URL (los WebSocket del celular no mandan encabezados) y uvicorn escribe esa URL en los logs de Render. Con el token cualquiera que lea los logs podría entrar como ese vecino. Este filtro lo cambia por `token=***` antes de escribir la línea.

- `RedactTokens`: Filtro de logging que reemplaza token=... por token=*** en cada línea.
  - `RedactTokens.filter`: Censura el token en el mensaje y deja pasar la línea (nunca la descarta).
- `install`: Agrega el filtro a los loggers de uvicorn (una sola vez). Se llama al iniciar la app.

#### `mi_barrio_backend/app/core/lookup_limit.py`

Límite de consultas públicas por IP (en memoria), para que no se puedan adivinar códigos de barrio probando miles de combinaciones.

- `check_and_count`: Cuenta una consulta; lanza 429 si la IP superó el límite de la ventana.

#### `mi_barrio_backend/app/core/rate_limit.py`

Límite de intentos fallidos de login (en memoria, suficiente para la hackathon). • Máximo 5 fallos por correo + IP en 5 minutos. • Máximo 30 fallos por IP en 5 minutos (evita probar muchos correos). Al iniciar sesión bien, se limpia el contador de ese correo + IP.

- `retry_after`: Segundos de espera si está bloqueado; 0 si puede intentar.
- `register_failure`: Anota un intento fallido (contraseña o código) para ese correo e IP.
- `register_success`: Borra los intentos fallidos de ese correo e IP tras un acceso correcto.

#### `mi_barrio_backend/app/core/realtime.py`

Conexiones WebSocket abiertas, para avisar al instante (chat de favores).

Vive en memoria: el backend corre en UN proceso (ver docker-entrypoint.sh). Si algún día se escala a varios procesos, esto pasa a Redis pub/sub.

- `RealtimeHub`: Conexiones WebSocket abiertas por usuario (para el chat en vivo). Vive en memoria del proceso.
  - `RealtimeHub.connect`: Registra un WebSocket abierto del usuario.
  - `RealtimeHub.disconnect`: Quita el WebSocket del usuario; si no le quedan, deja de figurar en línea.
  - `RealtimeHub.is_online`: True si el usuario tiene al menos una conexión abierta.
  - `RealtimeHub.send`: Envía a todos los teléfonos abiertos de esos usuarios. Un socket caído se descarta sin afectar a los demás.

#### `mi_barrio_backend/app/core/tenant_middleware.py`

Seguridad por barrio: rutas públicas, token de sesión, X-Tenant-ID y permisos por rol.

- `account_is_suspended`: La cuenta existe pero el jefe del barrio todavía no la reactivó.
- `account_is_active`: El token es válido solo si la cuenta sigue activa, en el mismo barrio y con el mismo rol. Así una cuenta borrada o degradada deja de operar al instante.
- `TenantMiddleware`: Middleware global que intercepta las peticiones a /api/v1/ y valida la presencia y formato del header X-Tenant-ID, inyectándolo en request.state.tenant_id.
  - `TenantMiddleware.dispatch`: Revisa cada petición: rutas públicas pasan; el resto necesita token válido y X-Tenant-ID del mismo barrio del token.
- `get_current_tenant_id`: Dependencia FastAPI para inyectar directamente el UUID validado del tenant en cualquier endpoint.
- `get_current_principal`: Dependencia: datos del token de la petición (sub, tenant_id, role). 401 si no hay sesión.
- `require_role`: Construye una dependencia que permite solo los roles indicados. Acepta los nombres de dominio históricos de la API (SUPER_ADMIN y ADMIN_BARRIO) y sus alias de UX (superadmin y admin).

### Backend: Piezas compartidas

#### `mi_barrio_backend/app/shared/base_model.py`

Columnas comunes (mixin) de las tablas que pertenecen a un barrio.

- `BarrioBaseMixin`: Columnas comunes de las tablas por barrio: id, tenant_id, borrado lógico y fechas para el sync (updated_at / server_updated_at).

#### `mi_barrio_backend/app/shared/contract_values.py`

Valores permitidos del contrato de datos (memoria técnica, sección 4.2).

Se usan como `Literal` en los schemas de creación: Swagger los muestra como lista desplegable y su ejemplo por defecto ya es válido (antes guardaba "string"). Los schemas de respuesta siguen aceptando `str` para no romper con datos viejos.


#### `mi_barrio_backend/app/shared/geo_utils.py`

Cálculos de distancia para ordenar por cercanía (sin servicios de mapas).

- `haversine_km`: Distancia en kilómetros entre dos coordenadas GPS (fórmula de haversine).

### Backend: Cuentas, barrios y perfil

#### `mi_barrio_backend/app/features/auth_barrio/account_codes.py`

Códigos de 6 dígitos por correo: verificar el correo y recuperar la contraseña.

- `debug_codes_enabled`: Solo para pruebas locales: devuelve el código en la respuesta. Requiere AUTH_DEBUG_CODES=1 Y que el correo NO esté configurado, así que en producción (con SMTP) nunca se activa aunque alguien deje la variable puesta.
- `issue_code`: Crea un código nuevo (invalida los anteriores) y lo devuelve. Lanza 429 si se pidió hace menos de 60 s o más de 5 veces en una hora.
- `consume_code`: Marca el código como usado. Lanza 400 si no es válido, venció o se agotó.

#### `mi_barrio_backend/app/features/auth_barrio/account_router.py`

Cuentas reales: verificar el correo, recuperar la contraseña y entrar con Google.

Todas estas rutas son públicas (no piden sesión ni X-Tenant-ID) y nunca revelan si un correo está registrado: pedir un código para un correo que no existe responde igual que para uno que sí.

- `send_verification_code` · **POST /api/v1/auth/email/send-code**: Reenvía el código para confirmar el correo. Responde igual exista o no la cuenta (no revela correos).
- `verify_email` · **POST /api/v1/auth/email/verify**: Confirma el correo con el código de 6 números y devuelve la sesión. Limita los intentos por correo e IP.
- `forgot_password` · **POST /api/v1/auth/password/forgot**: "¿Olvidaste tu contraseña?": envía un código al correo. Responde igual exista o no la cuenta.
- `reset_password` · **POST /api/v1/auth/password/reset**: Cambia la contraseña con el código del correo y deja la sesión iniciada. Limita los intentos.
- `set_password` · **POST /api/v1/auth/password/set**: Quien entró con Google crea su contraseña (pide sesión iniciada). Solo sirve si la cuenta todavía no tiene contraseña: para cambiar una que ya existe se usa "Olvidé mi contraseña" (con el código del correo).
- `google_login`: Entra o crea la cuenta con una identidad de Google ya verificada.
- `login_with_google` · **POST /api/v1/auth/google**: Entra con Google, o crea la cuenta la primera vez (428 si falta el código del barrio).

#### `mi_barrio_backend/app/features/auth_barrio/auth_router.py`

Cuentas: registro, login, sesión actual y gestión de barrios del superadministrador.

- `ensure_not_suspended`: Cuenta suspendida por reportes: no entra y se le dice con quién hablar.
- `register` · **POST /api/v1/auth/register**: Crea la cuenta (vecino o comerciante) en el barrio del código, envía el código de verificación al correo y devuelve la sesión.
- `login` · **POST /api/v1/auth/login**: Inicia sesión con correo y contraseña. Tras varios intentos fallidos pide esperar (429).
- `current_user` · **GET /api/v1/auth/me**: Datos de la cuenta de la sesión actual (para restaurar la sesión al abrir la app).
- `delete_unverified_account` · **DELETE /api/v1/auth/unverified-account**: "Volver para cambiar datos": borra la cuenta que nunca confirmó su correo, así el vecino puede registrarse de nuevo (con el mismo u otro correo).
- `create_neighborhood`: Solo superadministrador: crea un barrio (o usa uno existente por su código) y su administrador.
- `list_neighborhoods` · **GET /api/v1/platform/neighborhoods**: Solo superadministrador: lista los barrios con su código y si tienen administrador.

#### `mi_barrio_backend/app/features/auth_barrio/models.py`

Tablas de barrios, cuentas, superadministradores y códigos de correo.

- `Tenant`: Un barrio: nombre, código para unirse, centro en el mapa y si está en Modo Emergencia.
- `User`: Una cuenta de vecino, comerciante o administrador del barrio, con su perfil y su forma de entrar (contraseña o Google).
- `PlatformAdmin`: Cuenta global, fuera de cualquier barrio.
- `AuthCode`: Código de 6 dígitos enviado por correo (verificar correo o recuperar contraseña). Solo se guarda la huella HMAC del código. Vence a los 15 minutos y se invalida tras 5 intentos fallidos o al usarse.

#### `mi_barrio_backend/app/features/auth_barrio/platform_admin_bootstrap.py`

Crea el PRIMER superadministrador (solo funciona una vez por base de datos).

Uso (desde mi_barrio_backend): DATABASE_URL='postgresql://...neon.tech/...' .venv/bin/python -m app.features.auth_barrio.platform_admin_bootstrap

Sin DATABASE_URL en el entorno usa la de .env (la base local). Antes de pedir los datos muestra en qué servidor se va a crear la cuenta.

- `create_platform_admin`: Pide por consola nombre, correo y contraseña y crea el primer superadministrador. Solo funciona una vez: si ya existe uno, se detiene.

#### `mi_barrio_backend/app/features/auth_barrio/profile_router.py`

Perfil propio: ver el perfil completo y borrar la cuenta (derecho de cancelación).

- `get_my_profile` · **GET /api/v1/users/me**: Perfil completo del vecino autenticado (redes y perfil de publicador incluidos). La app lo usa para recuperar el perfil en un teléfono nuevo; los cambios suben por /sync/push (tabla `users`, solo la fila propia).
- `delete_my_account` · **DELETE /api/v1/users/me**: Borra la cuenta del vecino autenticado (derecho de cancelación, Ley 29733). • Sus datos personales se borran (nombre, correo, teléfono, redes, fotos, Google). • Su contenido se marca como borrado (is_deleted) para que el pull lo quite de todos los celulares del barrio, y se le quitan las fotos. • El token deja de servir: el middleware rechaza usuarios borrados. • El correo queda libre para crear otra cuenta.

#### `mi_barrio_backend/app/features/auth_barrio/router.py`

Barrio de la sesión: datos, código de invitación y Modo Emergencia.

- `get_tenant_by_code` · **GET /api/v1/tenants/by-code/{code}**: Público (sin sesión): confirma a qué barrio pertenece un código de invitación antes de registrarse ("Te vas a unir a: ..."). Solo devuelve nombre y centro; limitado a 30 consultas cada 5 minutos por IP para que no se adivinen códigos.
- `get_current_tenant` · **GET /api/v1/tenants/current**: Datos del barrio del header `X-Tenant-ID` (nombre, centro y Modo Emergencia).
- `get_invite_code` · **GET /api/v1/tenants/invite-code**: Código para invitar vecinos al barrio de la sesión.
- `toggle_emergency` · **PATCH /api/v1/tenants/emergency-toggle**: Activa o desactiva el Modo Emergencia para TODO el barrio. Los celulares lo reciben en el siguiente pull (`tenant.is_emergency_active`). Solo el administrador del barrio (ADMIN_BARRIO) puede hacerlo.

#### `mi_barrio_backend/app/features/auth_barrio/schemas.py`

Esquemas (Pydantic) de cuentas, barrios y códigos de correo.

- `TenantResponse`: Datos públicos del barrio (junta vecinal).
- `EmergencyToggleRequest`: Cuerpo para activar o desactivar el Modo Emergencia del barrio.
- `RegisterRequest`: Datos para crear una cuenta con correo y contraseña.
- `LoginRequest`: Correo y contraseña para iniciar sesión.
- `AuthUserResponse`: La cuenta tal como la ve la app tras entrar (sin datos sensibles).
- `AuthResponse`: Respuesta al entrar: token de sesión + la cuenta.
- `EmailRequest`: Solo un correo (para pedir códigos).
- `VerifyEmailRequest`: Correo + código de 6 números para confirmarlo.
- `ResetPasswordRequest`: Correo + código + contraseña nueva.
- `GoogleLoginRequest`: ID token de Google y, solo la primera vez, el código del barrio y el rol.
- `SetPasswordRequest`: Contraseña nueva para quien entró con Google y aún no tiene una.
- `CodeSentResponse`: Respuesta al pedir un código: siempre el mismo mensaje, exista o no la cuenta.
- `NeighborhoodAdminCreate`: Datos del superadministrador para crear un barrio y su administrador.
  - `NeighborhoodAdminCreate.require_coordinates_for_new_neighborhood`: Un barrio nuevo necesita nombre y coordenadas; uno existente se indica por su código.
- `NeighborhoodAdminCreated`: Barrio y administrador recién creados.
- `TenantLookupResponse`: Lo mínimo para confirmar el barrio antes de registrarse (ruta pública).
- `UserProfileResponse`: Perfil completo del propio vecino (GET /users/me). Nunca se expone el de otros.

#### `mi_barrio_backend/app/features/auth_barrio/service.py`

Funciones de cuentas y barrios usadas por varios routers (nombre corto público, contactos, emergencia).

- `public_name`: Nombre que ven los demás vecinos: nombre + inicial ("Rosa Calle" → "Rosa C.").
- `public_profiles`: Nombre público y contacto (teléfono / WhatsApp que el vecino cargó en su perfil) de cuentas activas del barrio. Nunca correo ni datos de otro barrio.
- `get_tenant_or_404`: El barrio por su id, o 404 si no existe.
- `set_emergency`: Activa o desactiva el Modo Emergencia del barrio.

### Backend: Chat entre vecinos

#### `mi_barrio_backend/app/features/chat/models.py`

Tabla de mensajes del chat entre vecinos (por favor o por servicio).

- `ChatMessage`: Mensaje de una conversación sobre un favor o un servicio. Conversación = (tipo, publicación, vecino que escribe al dueño). El dueño es el autor del favor o el comerciante del servicio.

#### `mi_barrio_backend/app/features/chat/router.py`

Chat en tiempo real entre vecinos sobre un favor o un servicio. • Enviar: REST (queda guardado aunque el otro no esté conectado). • Recibir al instante: WebSocket /api/v1/ws/chat. • Conversación = (tipo, publicación, vecino). El dueño (autor del favor o comerciante) ve todas las de su publicación; cada vecino, solo la suya.

- `inbox` · **GET /api/v1/chat/inbox**: "Mis mensajes": todas mis conversaciones (como dueño o como vecino), la más reciente primero.
- `list_conversations` · **GET /api/v1/chat/{kind}/{context_id}/conversations**: El dueño ve todas las conversaciones de su publicación; otro vecino, solo la suya.
- `list_messages` · **GET /api/v1/chat/{kind}/{context_id}/conversations/{neighbor_id}/messages**: Mensajes de una conversación (dueño de la publicación y un vecino). Solo la ven sus dos participantes.
- `send_message`: Guarda el mensaje y lo entrega AL INSTANTE (WebSocket) a los dos participantes.
- `chat_socket` · **WEBSOCKET /api/v1/ws/chat**: Canal en tiempo real: el teléfono se conecta con su token y recibe al instante los mensajes de sus conversaciones. Los WebSocket no pasan por el middleware HTTP: la sesión se valida aquí.

#### `mi_barrio_backend/app/features/chat/schemas.py`

Esquemas (Pydantic) del chat.

- `MessageCreate`: Texto de un mensaje nuevo (1 a 1000 caracteres).
- `MessageResponse`: Un mensaje del chat con su conversación y quién lo envió.
- `ConversationSummary`: Una conversación (dueño ↔ un vecino) de una publicación.

### Backend: Modo emergencia

#### `mi_barrio_backend/app/features/emergency_support/models.py`

Tablas de emergencia: pedidos de ayuda (SOS) y grupos de apoyo.

- `VulnerableReport`: Pedido de ayuda en emergencia (SOS): urgencia, tipo, ubicación y quién va a ayudar.
- `SupportGroup`: Grupo de apoyo del barrio (brigada, albergue, olla común...). Lo administra la junta.

#### `mi_barrio_backend/app/features/emergency_support/router.py`

Modo emergencia: pedir ayuda (SOS), tablero de pedidos, "voy en camino" y grupos de apoyo.

- `report_vulnerability` · **POST /api/v1/emergency/sos**: Crea un pedido de ayuda (SOS) a nombre del usuario de la sesión.
- `list_emergency_board` · **GET /api/v1/emergency/board**: Tablero de emergencia: pedidos de ayuda del barrio, los más recientes primero. Se puede filtrar por urgencia y estado.
- `attend_emergency_report` · **PATCH /api/v1/emergency/{report_id}/attend**: "Voy en camino": marca que el usuario va a ayudar. No se puede en el propio pedido ni en uno ya atendido.
- `list_support_groups` · **GET /api/v1/emergency/support-groups**: Grupos de apoyo activos del barrio. Con `lat` y `lng`, del más cercano al más lejano (los que no tienen ubicación van al final); sin ellos, por nombre.
- `create_support_group` · **POST /api/v1/emergency/support-groups**: Registra un grupo de apoyo. Solo el administrador del barrio (ADMIN_BARRIO).

#### `mi_barrio_backend/app/features/emergency_support/schemas.py`

Esquemas (Pydantic) de emergencia.

- `VulnerableReportBase`: Campos comunes de un pedido de ayuda (SOS).
- `VulnerableReportCreate`: Datos para crear un SOS (valores del contrato).
- `VulnerableReportResponse`: Un SOS como lo devuelve la API.
- `SupportGroupCreate`: Datos para registrar un grupo de apoyo del barrio (brigada, rescate…).
- `SupportGroupResponse`: Un grupo de apoyo como lo devuelve la API.

### Backend: Moderación

#### `mi_barrio_backend/app/features/moderation/models.py`

Tabla de reportes de publicaciones (moderación).

- `ContentReport`: Reporte de un vecino sobre un favor del muro o un servicio. Llega por el sync (funciona sin internet). Con 3 reportes de vecinos distintos la publicación pasa a revisión (`is_under_review`) hasta que el administrador del barrio o el superadministrador decida.

#### `mi_barrio_backend/app/features/moderation/router.py`

Moderación: el admin del barrio y el superadministrador revisan publicaciones reportadas.

- `ReportReasonItem`: Un motivo de reporte y su detalle escrito.
- `ReportedItem`: Publicación reportada con sus motivos, para el panel de revisión.
- `PendingCount`: Cantidad de publicaciones esperando revisión.
- `list_reports` · **GET /api/v1/moderation/reports**: Publicaciones reportadas del barrio (las que están en revisión primero).
- `count_reports` · **GET /api/v1/moderation/reports/count**: Admin del barrio: cuántas publicaciones esperan revisión.
- `resolve_report` · **POST /api/v1/moderation/reports/{target_type}/{target_id}/{action}**: `restore` la vuelve a mostrar; `remove` la elimina.
- `SuspendedAccount`: Cuenta suspendida por reportes, para el panel del jefe del barrio.
- `list_suspended` · **GET /api/v1/moderation/suspended**: Vecinos suspendidos por reportes, los más recientes primero.
- `reactivate_account` · **POST /api/v1/moderation/suspended/{user_id}/reactivate**: El vecino habló con el jefe del barrio: vuelve a usar la app.
- `platform_list_reports` · **GET /api/v1/platform/reports**: Superadministrador: publicaciones reportadas de todos los barrios.
- `platform_count_reports` · **GET /api/v1/platform/reports/count**: Superadministrador: cuántas publicaciones esperan revisión en total.
- `platform_resolve_report` · **POST /api/v1/platform/reports/{target_type}/{target_id}/{action}**: Superadministrador: restaurar o retirar una publicación reportada.

#### `mi_barrio_backend/app/features/moderation/service.py`

Moderación vecinal: reportes, revisión automática y decisión del administrador.

- `load_target`: La publicación reportada (favor o servicio), opcionalmente solo dentro de un barrio. ValueError si el tipo no existe.
- `validate_new_report`: La publicación existe en el barrio, no es propia y "Otro" trae el motivo escrito.
- `apply_review_threshold`: Con 3 reportes pendientes de vecinos distintos, la publicación pasa a revisión. Devuelve True si acaba de pasar a revisión.
- `owner_of`: Id del autor de la publicación reportada (favor o servicio).
- `reporters_against`: Cuántos vecinos DISTINTOS reportaron publicaciones de [user] (desde su última reactivación).
- `apply_suspension_threshold`: Con reportes de 3 vecinos distintos, la cuenta se suspende. Devuelve True si acaba de suspenderse.
- `admin_names`: Nombres de los jefes del barrio (para decirle al vecino con quién hablar).
- `suspended_message`: Mensaje para quien tiene la cuenta suspendida, con los nombres de los jefes del barrio que pueden reactivarla.
- `list_suspended`: Cuentas suspendidas del barrio (las más recientes primero) con cuántos vecinos las reportaron.
- `reactivate`: El jefe del barrio reactiva la cuenta. Los reportes anteriores dejan de contar: hacen falta 3 reportes NUEVOS para volver a suspenderla.
- `notify_admins`: Aviso al instante a los administradores del barrio que tengan la app abierta.
- `pending_count`: Cuántas publicaciones tienen reportes sin resolver.
- `list_reported`: Publicaciones con reportes pendientes, las que están en revisión primero.
- `resolve`: `restore`: vuelve a mostrarse. `remove`: se elimina. Los reportes quedan resueltos.

### Backend: Servicios del barrio

#### `mi_barrio_backend/app/features/proximity_services/models.py`

Tablas de servicios del barrio y sus reseñas (vistos buenos).

- `LocalService`: Un servicio u oficio publicado en el barrio (Necesito / Ofrezco), con fotos, precio y calificaciones.
- `NeighborEndorsement`: Visto bueno o reseña de un vecino a un servicio (estrellas, comentario, foto y respuesta del dueño).

#### `mi_barrio_backend/app/features/proximity_services/router.py`

Servicios del barrio: publicar, listar, fotos, reseñas y respuestas del dueño.

- `create_service` · **POST /api/v1/services**: Publica un servicio a nombre del usuario de la sesión (vecinos y comerciantes).
- `list_services` · **GET /api/v1/services**: Oficios del barrio con su promedio de estrellas. Orden: mejor promedio → más calificaciones → más recientes.
- `list_my_services` · **GET /api/v1/services/mine**: Servicios publicados por el usuario de la sesión.
- `endorse_service` · **POST /api/v1/services/endorse**: Registra un visto bueno y, opcionalmente, estrellas, comentario y foto. Un visto bueno por vecino y servicio: si ya existe, se actualiza (upsert).
- `list_service_endorsements` · **GET /api/v1/services/{service_id}/endorsements**: Vistos buenos y reseñas de un servicio.
- `get_service_photos` · **GET /api/v1/services/{service_id}/photos**: Fotos del servicio (aparte, para que la lista y el pull pesen poco).
- `reply_to_recommendation` · **POST /api/v1/services/{service_id}/recommendations/{rec_id}/reply**: El dueño del servicio responde una reseña.
- `get_endorsement_photo` · **GET /api/v1/endorsements/{endorsement_id}/photo**: Foto de una reseña (se pide aparte para no cargar todas las fotos en la lista).

#### `mi_barrio_backend/app/features/proximity_services/schemas.py`

Esquemas (Pydantic) de servicios y reseñas.

- `LocalServiceBase`: Campos comunes de un servicio.
- `LocalServiceCreate`: Datos para publicar un servicio (valores del contrato).
- `LocalServiceResponse`: Un servicio como lo devuelve la API, con su calificación.
- `NeighborEndorsementCreate`: Datos de un visto bueno o reseña nueva.
- `NeighborEndorsementResponse`: Una reseña como la devuelve la API.
- `EndorsementPhotoResponse`: Foto de una reseña en base64.
- `EndorsementReplyRequest`: Respuesta del dueño a una reseña.
- `ServicePhotosResponse`: Fotos de un servicio en base64.

#### `mi_barrio_backend/app/features/proximity_services/service.py`

Lógica de calificaciones con estrellas (compartida por el router y el sync).

- `rating_avg_subquery`: Subconsulta (service_id, rating_avg) para unir con local_services.
- `rating_avg_by_service`: Promedio de estrellas por servicio del barrio (1 decimal).
- `rating_avg_for_service`: Promedio de estrellas de UN servicio (1 decimal; None = sin estrellas).
- `provider_contacts`: Teléfono y WhatsApp de quien OFRECE un servicio en el barrio (cuentas activas).
- `recalculate_service_rating`: Actualiza el total de vistos buenos y marca el servicio para el pull. El promedio solo considera opiniones con estrellas; el contador también incluye vistos buenos sin calificación, que son válidos en el cliente.

### Backend: Muro de apoyo

#### `mi_barrio_backend/app/features/solidarity_network/models.py`

Tablas del muro de apoyo: favores, comentarios y calificaciones.

- `SolidarityPost`: Un favor del muro de apoyo: pido u ofrezco ayuda, con modalidad, fotos, ubicación y estado.
- `PostComment`: Comentario público de un vecino en un favor.
- `FavorReview`: Reseña al completar un favor: el autor califica a quien ayudó y viceversa.

#### `mi_barrio_backend/app/features/solidarity_network/router.py`

Muro de apoyo: favores, "voy a ayudar", comentarios y calificaciones.

- `create_solidarity_post` · **POST /api/v1/solidarity**: Publica un favor a nombre del usuario de la sesión.
- `list_solidarity_posts` · **GET /api/v1/solidarity**: Favores del barrio que no están borrados (se puede filtrar por tipo: SOLICITO_AYUDA u OFREZCO_AYUDA).
- `get_solidarity_post` · **GET /api/v1/solidarity/{post_id}**: Un favor del barrio por su id.
- `get_solidarity_post_photo` · **GET /api/v1/solidarity/{post_id}/photo**: La foto va aparte para que el muro y el pull pesen poco.
- `get_solidarity_post_photos` · **GET /api/v1/solidarity/{post_id}/photos**: Todas las fotos del favor (hasta 4). Las apps viejas usan /photo (la primera).
- `coordinate_solidarity_post` · **PATCH /api/v1/solidarity/{post_id}/coordinate**: "Voy a ayudar": el usuario se ofrece para el favor. No se puede en el propio.
- `delete_solidarity_post` · **DELETE /api/v1/solidarity/{post_id}**: Borra un favor. Solo quien lo publicó.
- `list_comments` · **GET /api/v1/solidarity/{post_id}/comments**: Comentarios públicos de un favor.
- `create_comment` · **POST /api/v1/solidarity/{post_id}/comments**: Agrega un comentario público al favor.
- `delete_comment` · **DELETE /api/v1/solidarity/{post_id}/comments/{comment_id}**: Borra un comentario. Solo su autor.
- `list_reviews` · **GET /api/v1/solidarity/{post_id}/reviews**: Calificaciones entre vecinos de un favor terminado.
- `create_review` · **POST /api/v1/solidarity/{post_id}/reviews**: Solo cuando el favor está COMPLETADO: el autor califica a quien ayudó y quien ayudó califica al autor. Una reseña por persona y favor.

#### `mi_barrio_backend/app/features/solidarity_network/schemas.py`

Esquemas (Pydantic) del muro de apoyo.

- `SolidarityPostBase`: Campos comunes de un favor.
- `SolidarityPostCreate`: Datos para publicar un favor (valores del contrato).
- `SolidarityPostResponse`: Un favor como lo devuelve la API.
- `PostPhotoResponse`: La primera foto del favor (apps anteriores).
- `PostPhotosResponse`: Todas las fotos del favor (hasta 4).
- `CommentCreate`: Texto de un comentario nuevo.
- `CommentResponse`: Un comentario con el nombre corto de su autor.
- `ReviewCreate`: Calificación (1 a 5 estrellas) y comentario opcional.
- `ReviewResponse`: Una calificación con los nombres de quién califica y a quién.

### Backend: Sincronización offline-first

#### `mi_barrio_backend/app/features/sync_engine/router.py`

Sincronización offline-first: push (subir cambios) y pull (bajar el delta del barrio).

- `push_offline_mutations` · **POST /api/v1/sync/push**: Recibe los cambios hechos sin internet (lote) y los aplica con "gana el último" (LWW). Devuelve los rechazados con su motivo.
- `pull_delta` · **GET /api/v1/sync/pull**: Cambios del barrio desde el último pull + estado del barrio (Modo Emergencia). Filtra por `server_updated_at` (reloj del servidor), no por `updated_at` (reloj del celular): así un post creado offline y subido tarde sí aparece.

#### `mi_barrio_backend/app/features/sync_engine/schemas.py`

Esquemas (Pydantic) del push y pull de sincronización.

- `MutationItem`: Un cambio hecho en el celular: tabla, id del registro, operación (UPSERT o DELETE) y sus datos (el payload lleva updated_at para LWW).
- `SyncPushRequest`: Lote de cambios que sube la app.
- `RejectedMutation`: Un cambio que el servidor no aceptó y por qué.
- `SyncPushResponse`: Resultado del push: cuántos se aplicaron, cuáles no y la hora del servidor.
- `TenantInfo`: Estado del barrio que viaja en cada pull (la app lo usa para el Modo Emergencia).
- `SyncPullResponse`: Cambios del barrio desde la última vez (delta por tabla), datos del barrio y si hay más páginas.

#### `mi_barrio_backend/app/features/sync_engine/service.py`

Lógica del sync: validar y aplicar cambios (LWW) y armar el delta paginado del pull.

- `process_sync_push`: Procesa el lote del celular. Cada mutación va en su propio SAVEPOINT: si una falla (dato inválido, servicio inexistente, etc.) se descarta solo esa y el resto del lote se guarda igual. La que falló no vuelve en processed_record_ids, así que queda en la cola del celular; el motivo se informa en `rejected`.

#### `mi_barrio_backend/app/features/sync_engine/validation.py`

Validación de los payloads del sync con las MISMAS reglas que las rutas REST.

El sync es una segunda puerta a la base de datos: si no valida igual que REST, se puede guardar por ahí lo que REST rechaza (lat=999, status inventados, fotos de 3 MB...). Cada error lanza ValueError con un mensaje claro, que el sync devuelve en `rejected` para ese ítem.

- `validate_payload`: Valida solo los campos presentes (un update puede ser parcial).

---

Documentos relacionados: [Manual de usuario](manual_de_usuario.md) · [Documentos legales](legal/README.md) · [Guía de cuentas reales](CUENTAS_REALES.md)
