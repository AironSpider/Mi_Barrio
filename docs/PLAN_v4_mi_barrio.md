# PLAN v4 — Mi Barrio (unifica el plan de Adrian + la v3)

**Corte:** sábado 7, 08:30 → **Hora 13.5 de 48**. Entrega: **domingo 8, 19:00**.
**Regla de equipo:** todos trabajamos en el **mismo sprint**. Nadie avanza al siguiente hasta cerrar el checkpoint del actual. Si alguien termina antes, ayuda o prueba, no adelanta pantallas.

---

## 🚦 Estado del Sprint 5 (actualizado sáb 09:40, H14.7)

| Parte | Estado |
|---|---|
| **Checkpoint 1** | ✅ **APROBADO contra el backend real:** post creado sin red → `PENDING` → reconexión → fila en PostgreSQL con el mismo UUID (test `test/e2e/checkpoint1_e2e_test.dart` de SoyJust). |
| **Dev 2** | ✅ Sync automático, pull seguro, SQLite v3, estrellas (UUID v5), perfil, distancia, estado de emergencia. |
| **Dev 1** (lo cubrió Dandy mientras Adrian descansa) | ✅ Swagger con `X-Tenant-ID` en todas las rutas · migración `a7c3e91f5b20` (`rating`, `photo_b64`, `publisher_type`, `publisher_name`) · `/sync/push` acepta `neighbor_endorsements`, recalcula el contador y **un ítem inválido ya no tumba el lote** · `/sync/pull` y `GET /services` devuelven `rating_avg` · `/services/endorse` hace upsert con estrellas (200). 15 pruebas contra PostgreSQL real en verde. |
| **Dev 3** | ⏳ **Falta:** paleta naranja, 4 pestañas fijas, kit (`sync_status_chip`, estrellas, `emergency_toggle`, filtros) y actualizar los tests del Sprint 1. |

**Adrian, al despertar:** `git pull` y luego `alembic upgrade head` (hay 1 migración nueva). Archivos tuyos modificados: `core/tenant_middleware.py` (el tenant como `Header`), `proximity_services/{models,schemas,router,service}.py` y `sync_engine/{service,router}.py`. La lógica LWW es la tuya; se agregó un SAVEPOINT por ítem y la búsqueda de calificaciones por (servicio, vecino). Tu siguiente tarea es la del **Sprint 6**.

**Cuando Dev 3 termine el kit → todos pasamos juntos al Sprint 6.**

---

## 1. Qué cambia respecto a los planes anteriores

| Tema | Plan de Adrian | v3 | **v4 (decisión)** |
|---|---|---|---|
| Recomendaciones | "Visto Bueno" (contador) | Estrellas 1 a 5 con comentario y foto | **Estrellas 1 a 5.** La foto es lo primero que se recorta si falta tiempo. |
| Paleta | Verde | Naranja | **Naranja**, con las reglas de contraste de la sección 4. |
| Pestañas | Cambian con la emergencia | 4 fijas | **4 fijas:** Servicios, Apoyo, Mapa, Tú. |
| Toggle de emergencia | Switch de prueba en la AppBar | En Servicios y Apoyo, con podio | **Toggle en Servicios y Apoyo + podio "Prioridad 1-3".** |
| Módulo Tú | No existía | Perfil + historial | **Sí, pero después del Checkpoint 2.** Es lo primero que se recorta. |
| Sincronización | Sprint 4 | Sprint 4 | **Prioridad absoluta ahora (Checkpoint 1 atrasado).** |

---

## 2. Estado real del proyecto (revisado en el código, H13.5)

### ✅ Hecho
| Área | Qué funciona |
|---|---|
| **Backend** | Tablas `tenants`, `users`, `solidarity_posts`, `local_services`, `neighbor_endorsements` (con UNIQUE), `vulnerable_reports` y migraciones Alembic. Middleware `X-Tenant-ID`. `/sync/push` genérico (3 tablas, LWW). `/sync/pull` (posts y servicios). CRUD de solidaridad, servicios + endorse (sin duplicados), emergencia (SOS, board, attend). `/health`. |
| **App, núcleo offline** | SQLite v2 (`solidarity_posts`, `local_services`, `sync_outbox`, `sync_state`), migración sin perder datos, UUID v4 local, inserción `PENDING` + outbox en una transacción, validaciones. `ConnectivityMonitor`. `SyncWorker.pushLocalChanges` (solo limpia lo confirmado). |
| **App, UI** | Tema accesible, navegación, botón (+), modal de 3 clics conectado a SQLite ("Guardado en el teléfono"), `service_card`, `visto_bueno_badge`, directorio con datos demo. |
| **Calidad** | 36 tests automáticos (contraste, accesibilidad, SQLite offline, navegación). |

### ❌ Falta (ordenado por impacto en la demo)
1. **Sync automático:** nadie llama al `SyncWorker` al recuperar internet → **Checkpoint 1 no pasa todavía.**
2. El pull no guarda `local_services` en el teléfono, y además pisa cambios locales pendientes.
3. Android: falta el permiso `INTERNET` y `usesCleartextTraffic` en el manifest principal (el sync por `http://` falla fuera del modo debug).
4. El muro (Apoyo) y el mapa siguen siendo pantallas provisionales; el directorio usa datos fijos.
5. Swagger no muestra `X-Tenant-ID` en `/services` y `/emergency` (desde `/docs` siempre dan 400).
6. Todo lo nuevo de la v3: estrellas, paleta naranja, toggle con podio, módulo Tú.

---

## 3. Decisiones técnicas obligatorias (evitan bugs ya detectados)

1. **Calificación con id determinístico:** `id = UUID v5(service_id + endorser_user_id)`. La misma persona siempre genera el mismo id → el upsert funciona y el `UNIQUE` del backend nunca rompe el lote del push.
2. **Promedio de estrellas:** lo calcula el servidor (`AVG(rating)`) y viaja en el pull de `local_services` como `rating_avg`. En SQLite es una columna local de solo lectura. **El pull no trae fotos**; la foto se pide solo al abrir el detalle.
3. **Sin login todavía:** el backend solo conoce el barrio (`X-Tenant-ID`), no a la persona. "403 si no es tu fila" y "solo LIDER_VECINAL activa la emergencia" **no se pueden validar en el servidor** → se controlan en la app y se presentan como limitación conocida (respuesta para el jurado: "el siguiente paso es JWT por vecino").
4. **Sin dependencias nuevas salvo acuerdo:** el estado de emergencia se guarda en SQLite (no `shared_preferences`) y el ícono es `Icons.warning_amber_rounded` (no Font Awesome). `image_picker` solo si llegamos a la foto.
5. **Coordenadas del demo: Piura** (como el launcher actual y el seed). Centro: `-5.1945, -80.6328`.
6. **Barrio demo fijo** hasta el Sprint 9: `tenant_id = a1b2c3d4-e5f6-4a8b-9c0d-1e2f3a4b5c6d`, usuario `5f3a2c1b-1234-4abc-9def-0123456789ab`.
7. **URL del backend:** `--dart-define=API_BASE_URL=...`. Por defecto: emulador Android `http://10.0.2.2:8000`, Windows `http://localhost:8000`. Para un celular físico se usa la IP de la PC en la red.
8. **Booleanos:** `0/1` en SQLite y `true/false` en JSON (ya resuelto en los modelos).

---

## 4. Paleta naranja con contraste verificado (WCAG AA)

| Uso | Color | Contraste | Regla |
|---|---|---|---|
| Botón relleno (texto blanco) | `#D63A15` | 4.69:1 ✅ | Todos los botones |
| Texto / íconos naranja | `#A82B0C` | 6.96:1 ✅ | Sobre blanco, `#FDEBE6` y `#FFF1EC` |
| Fondo suave | `#FDEBE6` | — | Tarjetas seleccionadas |
| Pendiente | `#8A5300` sobre `#FFF3DC` | 5.76:1 ✅ | Ícono `schedule` + "Pendiente" |
| Sincronizado | `#A82B0C` | ✅ | Ícono `check_circle` + "Sincronizado" |
| Estrella llena / vacía | `#C46A00` / `#857A75` | 3.88 / 4.17 ✅ | Mínimo 3:1 para íconos |
| Etiquetas | `#27509D` sobre `#E6EEFB` | 6.61:1 ✅ | Chips de categoría |
| Acento `#F54927` | — | **3.58:1 ❌ con texto** | **Solo bordes, franjas y decoración** |
| Emergencia `#E3501B` | — | **3.87:1 ❌ con texto** | **Solo franja superior y bordes del podio** |

Los tests de contraste del repo fallan si un color no cumple: **actualizarlos junto con la paleta, no borrarlos.**

---

## 5. Sprints desde ahora (todos alineados)

> Formato: **Sprint N (horas, horario aproximado)**. Al final de cada sprint: `git pull`, `flutter test`, push y aviso en el grupo.

### Sprint 5 (H13.5–H17, sáb 08:30–12:00): **Checkpoint 1 + base v3**
- **Dev 1** (al volver de descansar):
  - Arreglar Swagger: `get_current_tenant_id` debe recibir `X-Tenant-ID` como `Header(...)` (hoy `/services` y `/emergency` dan 400 desde `/docs`).
  - [Aditivo] Migración A: `neighbor_endorsements.rating` (1-5, nullable) y `photo_b64` (nullable). Migración C: `local_services.publisher_type` y `publisher_name`.
  - `/sync/push`: aceptar `neighbor_endorsements` y recalcular `endorsements_count`. `/sync/pull`: devolver `rating_avg` en `local_services`.
- **Dev 2:**
  - **Sync automático:** al abrir la app, al volver internet y después de cada publicación → push + pull. Con `api_client` y `tenant_session` de demo.
  - Pull de `local_services`, sin pisar filas `PENDING`.
  - Manifest de Android: `INTERNET` + `usesCleartextTraffic`.
  - SQLite v3: `neighbor_endorsements` (rating, comentario, foto, id UUID v5), `users` (perfil + redes), `publisher_*` y `rating_avg` en `local_services`.
  - `shared/local_distance.dart` (haversine + tests) y `emergency_mode_provider.dart` (persistido en SQLite).
- **Dev 3:**
  - Paleta naranja (sección 4) y 4 pestañas fijas: Servicios, Apoyo, Mapa, Tú. Actualizar los tests del Sprint 1.
  - Kit en `ui_kit/`: `sync_status_chip`, `star_rating_display`, `star_rating_input`, `emergency_toggle`, `filter_pill`, `app_select_field`, `filters_bottom_sheet`.
- ✅ **Checkpoint 1:** publicar en modo avión → reconectar → la fila aparece en PostgreSQL con el mismo UUID.

### Sprint 6 (H17–H20, sáb 12:00–15:00): **Servicios con datos reales + podio**
- **Dev 1:** `PATCH /api/v1/tenants/emergency-toggle`, y que el pull devuelva `is_emergency_active` del barrio y los `vulnerable_reports`. **Importante para la demo con 2 celulares:** el pull filtra por `updated_at`, que viene del reloj del celular. Un post creado offline y subido horas después nunca le llega a quien ya sincronizó. Agregar `server_updated_at` (lo pone el servidor con `now()` en cada escritura) y filtrar el pull por ese campo.
- **Dev 2:** `rateService()` (upsert offline), consultas de servicios con promedio y orden, `shared/emergency_ranking.dart` (`rankServices`, `rankPosts`) con tests, `gps_service.dart` con fallback al centro del barrio.
- **Dev 3:** `services_directory_screen` leyendo SQLite (adiós datos demo): búsqueda, filtros, `emergency_toggle` y podio animado. `service_card` con estrellas de solo lectura y `sync_status_chip`.
- ✅ El toggle reordena Servicios con animación y aparecen los chips "Prioridad".

### Sprint 7 (H20–H23, sáb 15:00–18:00): **Apoyo (muro) + calificar**
- **Dev 1:** `scripts/seed_demo.py` (barrio de Piura, 6 oficios con estrellas, 4 favores, 3 reportes).
- **Dev 2:** cambio de estado de un favor (`EN_COORDINACION`, `COMPLETADO`) con outbox; `history_dao.dart` (consultas por autor).
- **Dev 3:** `collaborative_wall_screen` (píldoras, "Necesito | Ofrezco", toggle, podio, oculta COMPLETADO, chip de sync). `service_detail_sheet` (mini mapa `CustomPainter` + formulario de estrellas, sin foto por ahora). `favor_detail_sheet` con botón "Coordinar".
- ✅ Calificar un servicio offline → estrellas + "Pendiente" → reconectar → "Sincronizado".

### Sprint 8 (H23–H26, sáb 18:00–21:00): **Emergencia + Checkpoint 2**
- **Dev 1:** sync completo de `vulnerable_reports`; `GET /api/v1/emergency/support-groups`.
- **Dev 2:** tabla local `vulnerable_reports`, `emergency_sqlite_ds` (SOS con GPS, sin red), y que `emergency_mode_provider` lea la bandera del barrio; sync cada 15 s en emergencia y cada 60 s en modo normal.
- **Dev 3:** estilo de emergencia (franja `#E3501B`, chip, fondo `#FFF1EC`), Mapa en modo lista por cercanía, flujo SOS en 3 clics, `humanitarian_board_screen`.
- ✅ **Checkpoint 2:** el toggle cambia estilo, podio y Mapa en menos de 3 s, sin renombrar pestañas. Un SOS sin red sube al reconectar.

### Sprint 9 (H26–H29, sáb 21:00–00:00): **Tú + onboarding**
- **Dev 1:** `GET /tenants/by-code/{code}`, `POST /users/quick-register`, migración B (redes en `users`) y `users` en el sync. Pantalla `edit_profile_screen`.
- **Dev 2:** `tenant_session` real (barrio, nombre, rol, código); "Cambiar de barrio" / "Cerrar sesión" con aviso "Tienes N cambios sin sincronizar".
- **Dev 3:** `me_screen` (cabecera, barrio, 2 tarjetas), `tutorial_screen` (3 pasos), `select_barrio_screen`.

### Sprint 10 (H29–H32, dom 00:00–03:00): **Historial + robustez**
- **Dev 1:** `history_screen` (Mis Servicios / Mis Favores / Mis Alertas).
- **Dev 2:** reintentos con espera (2, 4, 8, 16 s); un ítem inválido no debe trabar el lote.
- **Dev 3:** barra "Modo offline — datos guardados en tu teléfono" / "Sincronizado con Mi Barrio".

### Sprint 11 (H32–H35, dom 03:00–06:00): **Datos finales y cercanía**
- Seed final en Piura · orden por cercanía de recursos y reportes · modal "Ofrecer ayuda" (`VECINOS_EN_CAMINO`).

### Sprint 12 (H35–H37, dom 06:00–08:00): **Pulido**
- Sin errores 500 en Swagger · 50 registros fluidos y cierre forzado sin pérdida · auditoría de 3 clics, 16 sp, 48 dp y contraste AA.

### Sprint 13 (H37–H40, dom 08:00–11:00): **FEATURE FREEZE + prueba en modo avión**
### Sprint 14 (H40–H43, dom 11:00–14:00): **Pitch (7 diapositivas) + video de respaldo de 60 s**
### Sprint 15 (H43–H46, dom 14:00–17:00): **Ensayos (3 veces, cronometrado)**
### Buffer (H46–H48, dom 17:00–19:00): **Entrega final en la nube**

---

## 6. Ruta crítica de la demo (no se recorta)
Publicar en 3 clics en modo avión → chip "Pendiente" → toggle de emergencia con podio → reconectar → "Sincronizado" → fila en PostgreSQL.

## 7. Si hay retraso, se recorta en este orden
1. Foto en calificación y perfil.
2. Historial (queda solo "Mis Favores").
3. Mapa para reubicar la casa (queda el GPS).
4. Radar del Mapa (queda la lista por cercanía).
5. Módulo Tú completo (queda la cabecera con el barrio).
6. Animaciones de pulido.

## 8. Reglas de Git (para no pisarnos)
- Antes de empezar: `git pull`. Antes de subir: `flutter test` en verde.
- Cada quien toca **solo los archivos de su rol**. Si necesitas cambiar un archivo de otro, avisa en el grupo primero.
- Commits cortos y claros. No subir `venv/`, `.env`, `build/`, `hs_err_pid*.log`.
- `main.dart` es compartido: Dev 2 solo toca la inicialización y Dev 3 solo `MaterialApp`/navegación.
