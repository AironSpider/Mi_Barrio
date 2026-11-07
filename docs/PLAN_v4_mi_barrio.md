# PLAN v4 — Mi Barrio (unifica el plan de Adrian + la v3)

**Corte:** sábado 7, 15:45 → **Hora 20.7 de 48**. Entrega: **domingo 8, 19:00**.
**Regla de equipo:** todos trabajamos en el **mismo sprint**. Si alguien termina antes, ayuda o prueba; no adelanta pantallas.

---

## 🚦 Estado actual (sáb 15:45) — Sprint 8 casi cerrado → luego **Sprint 9**

| Sprint 8 | Estado |
|---|---|
| **Dev 3** (estilo de emergencia, SOS en 3 clics, Mapa por cercanía, tablero humanitario) | ✅ Hecho y probado (capturas en `docs/preview_sprint8/`) |
| **Dev 2** (tabla local `vulnerable_reports`, SOS sin red, bandera del barrio en el pull, sync 15 s / 60 s) | ✅ Hecho: el SOS se guarda en SQLite + outbox y se sincroniza; la emergencia de la junta llega sola a todos los celulares |
| **Dev 1** (sync completo de `vulnerable_reports`) | ✅ (ya estaba desde el Sprint 6) |
| **Dev 1** (`GET /api/v1/emergency/support-groups`) | ❌ **Falta** → única tarea pendiente del Sprint 8 |

**✅ Checkpoint 2:** el ADMIN_BARRIO activa la emergencia desde su pantalla ("Emergencia del barrio") → en ≤ 60 s todos los vecinos ven la franja naranja, el chip "Emergencia", el botón **Pedir ayuda** y el tablero. En emergencia la app sincroniza cada 15 s.

### 🔐 Seguridad (auditoría ofensiva: de 12 a 25 defensas)
Corregido y probado contra PostgreSQL real:
- **Sync:** el dueño se valida también en el registro guardado (nadie edita ni borra posts, servicios ni SOS ajenos). Otro vecino solo puede marcar "Voy en camino" en un SOS.
- **Sync:** mismas validaciones que REST (valores del contrato, lat/lng, largos, foto ≤ 110 KB), máximo **200 cambios por envío** (413) y `updated_at` del celular limitado a **ahora + 5 min**.
- **Emergencia del barrio:** solo `ADMIN_BARRIO` (403 para vecinos y comerciantes).
- **Login:** el hash ya no congela el servidor; **máximo 5 intentos fallidos** por correo+IP en 5 min (429); el tiempo de respuesta no revela si un correo existe.
- **Cuentas borradas o con rol cambiado** dejan de funcionar al instante (antes: 24 h).
- **App:** si el token vence, **se conservan los cambios hechos sin internet** y se suben al volver a entrar la misma persona; si entra otra persona, se descartan.
- `.env` fuera del repositorio.

⚠️ **Cada uno debe generar su propia `MI_BARRIO_JWT_SECRET`**: la clave vieja quedó en el historial de Git (`de73af9`) y ya no es secreta.

### 🧪 Cómo verificar (todo en verde al corte)
| Prueba | Resultado |
|---|---|
| `scripts/smoke_test_api.py` (crea su propio barrio de prueba) | **46/46** |
| `scripts/test_sprint6_backend.py` (barrio propio) | **25/25** |
| `flutter analyze` | sin problemas |
| `flutter test --concurrency=1` | **108/108** (2 e2e se saltan si no hay `E2E_SUPER_ADMIN_*`) |

El barrio demo `BARRIO-01` quedó **limpio** (`scripts/limpiar_datos_prueba.py --aplicar` ocultó 60 registros de pruebas viejas).

### 📌 Deuda de sprints anteriores (NO está hecho)
| Pendiente | Sprint | Rol | Impacto en la demo |
|---|---|---|---|
| **Podio "Prioridad 1-3" + toggle en Servicios y Apoyo** | 6 | Dev 3 | 🔴 Está en la **ruta crítica de la demo** |
| `shared/emergency_ranking.dart` (`rankServices`, `rankPosts`) + tests | 6 | Dev 2 | 🔴 Lo necesita el podio |
| **`scripts/seed_demo.py`** (barrio de Piura con oficios, favores y SOS) | 7 | Dev 1 | 🔴 Hoy el barrio demo está vacío |
| `service_detail_sheet` (calificar con estrellas) y `favor_detail_sheet` ("Coordinar") | 7 | Dev 3 | 🟠 |
| Cambio de estado de favores + `history_dao.dart` | 7 | Dev 2 | 🟡 |
| `GET /api/v1/emergency/support-groups` | 8 | Dev 1 | 🟡 |
| Botón **"Cerrar sesión"** para vecinos (hoy solo lo tienen los admins) con aviso de cambios pendientes | 9 | Dev 2 + Dev 3 | 🟠 |

**Recomendación:** antes de abrir el Sprint 9, cerrar los 3 🔴 (podio, ranking, seed), porque sin ellos no se puede mostrar la ruta crítica.

### ▶️ Antes de seguir, todos
`git pull` → generar tu propia clave JWT → `alembic upgrade head` → `uvicorn` → `/health` (`migrations_up_to_date: true`) → `flutter test --concurrency=1`.

---

## 1. Qué cambia respecto a los planes anteriores

| Tema | Plan de Adrian | v3 | **v4 (decisión)** |
|---|---|---|---|
| Recomendaciones | "Visto Bueno" (contador) | Estrellas 1 a 5 con comentario y foto | **Estrellas 1 a 5** + "Visto bueno" sin estrellas. La foto es lo primero que se recorta. |
| Paleta | Verde | Naranja | **Paleta v2 por psicología del color** (sección 3): verde = economía local, naranja = emergencia, cian = etiquetas. |
| Pestañas | Cambian con la emergencia | 4 fijas | **4 fijas:** Servicios, Apoyo, Mapa, Tú. |
| Toggle de emergencia | Switch de prueba en la AppBar | En Servicios y Apoyo, con podio | **La junta la activa para todos** (pantalla del ADMIN_BARRIO); el podio en Servicios/Apoyo sigue pendiente. |
| Módulo Tú | No existía | Perfil + historial | **Sí, Sprint 9–10.** Es lo primero que se recorta. |
| Login | No había | — | **JWT por vecino** (VECINO, COMERCIANTE, ADMIN_BARRIO, SUPER_ADMIN). |

---

## 2. Decisiones técnicas obligatorias (evitan bugs ya detectados)

1. **Calificación con id determinístico:** `id = UUID v5(service_id + endorser_user_id)`; el servidor además busca por (servicio, vecino).
2. **Promedio de estrellas:** lo calcula el servidor y viaja como `rating_avg`. **El pull no trae fotos.**
3. **Seguridad en el servidor, no en la app:** el tenant y la persona salen del token; el dueño se valida en el registro guardado; las mismas reglas aplican a REST y al sync.
4. **Pull por `server_updated_at`** (reloj del servidor) con margen de 30 s; **LWW por `updated_at`** (reloj del celular, máximo ahora + 5 min).
5. **Coordenadas del demo: Piura.** Centro: `-5.1945, -80.6328`. Código del barrio demo: `BARRIO-01`.
6. **URL del backend:** `--dart-define=API_BASE_URL=...`. Por defecto: emulador `http://10.0.2.2:8000`, Windows `http://localhost:8000`; celular físico: IP de la PC y `uvicorn --host 0.0.0.0`.
7. **Booleanos:** `0/1` en SQLite y `true/false` en JSON.
8. **Las pruebas nunca escriben en el barrio demo:** usan `scripts/_test_env.py` (barrio de prueba propio).

---

## 3. Paleta v2 (psicología del color) con contraste verificado (WCAG AA)

La paleta del equipo es la **identidad**. Donde un color no alcanza el contraste con texto, se usa **el mismo tono más oscuro** (los tests del repo fallan si alguien usa un color ilegible).

| Rol | Color del equipo | Dónde se usa tal cual | Para texto / botones | Contraste |
|---|---|---|---|---|
| **Modo normal** (economía local) | `#2AA63E` | Íconos, Visto Bueno, indicadores | **`#1E7A2E`** con texto blanco | 5.4:1 ✅ (el original da 3.17 ❌ con texto) |
| **Modo emergencia** (máxima prioridad) | `#F54927` | Franja superior, bordes, selección del SOS | **`#C2381B`** con texto blanco | 5.4:1 ✅ (el original da 3.58 ❌) |
| **Etiquetas / píldoras** | `#21BCFF` | Fondo de píldora seleccionada | Texto **`#0F172A`** | 8.2:1 ✅ (tal como se propuso) |
| Fondo general | `#F3F4F6` | Lienzo de la app | — | — |
| Fondo en emergencia | `#FFF1EC` | Lienzo en emergencia | — | — |
| Tarjetas y modales | `#FFFFFF` | Muro, perfiles, hojas | — | — |
| Hover / selección | `#F8FAFC` | Al tocar tarjetas | — | — |
| Texto principal | `#1E293B` | Títulos, nombres | — | 13.3:1 ✅ |
| Texto secundario | `#64748B` → **`#606F85`** | Descripciones, horas | — | 4.6:1 ✅ (el original da 4.32 ❌ sobre `#F3F4F6`) |

**Estados (siempre ícono + texto, nunca solo color):** Pendiente `#8A5300` sobre `#FFF3DC` · Sincronizado `#166534` sobre `#E7F6EA` · Sin enviar `#B3261E` sobre `#FDECEA` · Urgencia Crítica `#B3261E`, Alta `#8A5300`, Media `#0369A1` · Estrellas `#C46A00` / `#7B8798`.

**En código:** `AppPalette` (valores) y `MiBarrioColors.of(context)` (colores según el modo: `brand`, `accentText`, `pill`, `onPill`...). Los componentes del kit ya cambian solos entre verde y naranja.

---

## 4. Sprints desde ahora (todos alineados)

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
  - Paleta naranja (sección 3) y 4 pestañas fijas: Servicios, Apoyo, Mapa, Tú. Actualizar los tests del Sprint 1.
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

## 5. Ruta crítica de la demo (no se recorta)
Publicar en 3 clics en modo avión → chip "Pendiente" → toggle de emergencia con podio → reconectar → "Sincronizado" → fila en PostgreSQL.

## 6. Si hay retraso, se recorta en este orden
1. Foto en calificación y perfil.
2. Historial (queda solo "Mis Favores").
3. Mapa para reubicar la casa (queda el GPS).
4. Radar del Mapa (queda la lista por cercanía).
5. Módulo Tú completo (queda la cabecera con el barrio).
6. Animaciones de pulido.

## 7. Reglas de Git (para no pisarnos)
- Antes de empezar: `git pull`. Antes de subir: `flutter test` en verde.
- Cada quien toca **solo los archivos de su rol**. Si necesitas cambiar un archivo de otro, avisa en el grupo primero.
- Commits cortos y claros. No subir `venv/`, `.env`, `build/`, `hs_err_pid*.log`.
- `main.dart` es compartido: Dev 2 solo toca la inicialización y Dev 3 solo `MaterialApp`/navegación.
