/// Esquema local de SQLite (espejo de PostgreSQL + tablas exclusivas del móvil).
///
/// Reglas del contrato de datos (memoria técnica, sección 4):
/// - `id` / `tenant_id`: TEXT con UUID v4 generado en el teléfono.
/// - Booleanos: INTEGER 0/1 en SQLite (se convierten a true/false al sincronizar).
/// - `updated_at`: TEXT ISO-8601 UTC.
/// - `sync_status`: solo en SQLite: 'PENDING' | 'SYNCED' | 'FAILED'.
///
/// Todas las sentencias usan IF NOT EXISTS, así que son seguras de re-ejecutar
/// (instalación nueva o actualización de una versión anterior).
class SqliteTables {
  SqliteTables._();

  /// Versión actual del esquema. Súbela al agregar tablas o columnas
  /// y añade el paso correspondiente en [migrations].
  static const int schemaVersion = 9;

  // ── Valores permitidos (idénticos al contrato del backend) ──
  static const syncPending = 'PENDING';
  static const syncSynced = 'SYNCED';
  static const syncFailed = 'FAILED';

  // ── Tablas de negocio ──

  static const createSolidarityPosts = '''
    CREATE TABLE IF NOT EXISTS solidarity_posts (
      id TEXT PRIMARY KEY,
      tenant_id TEXT NOT NULL,
      author_user_id TEXT NOT NULL,
      flow_type TEXT NOT NULL,
      modality TEXT NOT NULL,
      title TEXT NOT NULL,
      description TEXT,
      is_emergency_context INTEGER NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'DISPONIBLE',
      lat REAL NOT NULL,
      lng REAL NOT NULL,
      is_deleted INTEGER NOT NULL DEFAULT 0,
      updated_at TEXT NOT NULL,
      sync_status TEXT NOT NULL DEFAULT 'SYNCED',
      author_name TEXT,
      contact_phone TEXT,
      contact_whatsapp TEXT,
      has_photo INTEGER NOT NULL DEFAULT 0,
      coordinator_user_id TEXT,
      coordinator_name TEXT
    )
  ''';

  /// Fotos de favores (aparte: el pull reemplaza la fila del favor y no trae
  /// la foto; así no se pierde la que ya se descargó o se tomó aquí).
  static const createPostPhotos = '''
    CREATE TABLE IF NOT EXISTS post_photos (
      post_id TEXT PRIMARY KEY,
      tenant_id TEXT NOT NULL,
      photo_b64 TEXT NOT NULL
    )
  ''';

  static const createLocalServices = '''
    CREATE TABLE IF NOT EXISTS local_services (
      id TEXT PRIMARY KEY,
      tenant_id TEXT NOT NULL,
      provider_user_id TEXT NOT NULL,
      category TEXT NOT NULL,
      title TEXT NOT NULL,
      description TEXT NOT NULL DEFAULT '',
      is_available_in_emergency INTEGER NOT NULL DEFAULT 0,
      endorsements_count INTEGER NOT NULL DEFAULT 0,
      rating_avg REAL,
      publisher_type TEXT,
      publisher_name TEXT,
      contact_phone TEXT,
      contact_whatsapp TEXT,
      lat REAL NOT NULL,
      lng REAL NOT NULL,
      is_deleted INTEGER NOT NULL DEFAULT 0,
      updated_at TEXT NOT NULL,
      sync_status TEXT NOT NULL DEFAULT 'SYNCED',
      price_text TEXT,
      photo_count INTEGER NOT NULL DEFAULT 0
    )
  ''';

  /// Fotos de servicios (aparte: el pull no las trae y reemplaza la fila del
  /// servicio). Hasta 4 por servicio, en orden ([position] 0..3).
  static const createServicePhotos = '''
    CREATE TABLE IF NOT EXISTS service_photos (
      service_id TEXT NOT NULL,
      position INTEGER NOT NULL,
      tenant_id TEXT NOT NULL,
      photo_b64 TEXT NOT NULL,
      PRIMARY KEY (service_id, position)
    )
  ''';

  /// Calificación con estrellas (reemplaza al "Visto Bueno").
  /// Una por vecino y servicio: el id es UUID v5(service_id + endorser_user_id).
  static const createNeighborEndorsements = '''
    CREATE TABLE IF NOT EXISTS neighbor_endorsements (
      id TEXT PRIMARY KEY,
      tenant_id TEXT NOT NULL,
      service_id TEXT NOT NULL,
      endorser_user_id TEXT NOT NULL,
      rating INTEGER CHECK (rating IS NULL OR rating BETWEEN 1 AND 5),
      short_comment TEXT,
      photo_b64 TEXT,
      is_deleted INTEGER NOT NULL DEFAULT 0,
      updated_at TEXT NOT NULL,
      sync_status TEXT NOT NULL DEFAULT 'SYNCED',
      endorser_name TEXT,
      UNIQUE (service_id, endorser_user_id)
    )
  ''';

  /// Perfil del vecino (módulo "Tú").
  static const createUsers = '''
    CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY,
      tenant_id TEXT NOT NULL,
      full_name TEXT NOT NULL,
      phone TEXT NOT NULL DEFAULT '',
      address_reference TEXT,
      home_lat REAL NOT NULL,
      home_lng REAL NOT NULL,
      role TEXT NOT NULL DEFAULT 'VECINO',
      tutorial_completed INTEGER NOT NULL DEFAULT 0,
      email TEXT,
      email_contacto TEXT,
      whatsapp TEXT,
      facebook_url TEXT,
      instagram_url TEXT,
      photo_b64 TEXT,
      publisher_type TEXT,
      publisher_category TEXT,
      publisher_name TEXT,
      is_deleted INTEGER NOT NULL DEFAULT 0,
      updated_at TEXT NOT NULL,
      sync_status TEXT NOT NULL DEFAULT 'SYNCED'
    )
  ''';

  // ── Tablas exclusivas del dispositivo ──

  /// Preferencias locales (ej. toggle de emergencia del vecino).
  static const createAppSettings = '''
    CREATE TABLE IF NOT EXISTS app_settings (
      key TEXT PRIMARY KEY,
      value TEXT
    )
  ''';

  /// Cola de mutaciones pendientes de subir (Outbox Pattern).
  static const createSyncOutbox = '''
    CREATE TABLE IF NOT EXISTS sync_outbox (
      outbox_id INTEGER PRIMARY KEY AUTOINCREMENT,
      tenant_id TEXT NOT NULL,
      target_table TEXT NOT NULL,
      record_id TEXT NOT NULL,
      operation TEXT NOT NULL,
      payload_json TEXT NOT NULL,
      created_at TEXT NOT NULL
    )
  ''';

  /// Puntero de la última descarga incremental por barrio.
  static const createSyncState = '''
    CREATE TABLE IF NOT EXISTS sync_state (
      tenant_id TEXT PRIMARY KEY,
      last_pulled_at TEXT NOT NULL
    )
  ''';

  // ── Índices: todas las consultas filtran por barrio y estado de sync ──

  static const indexes = [
    'CREATE INDEX IF NOT EXISTS idx_solidarity_tenant '
        'ON solidarity_posts (tenant_id, is_deleted, updated_at)',
    'CREATE INDEX IF NOT EXISTS idx_solidarity_sync '
        'ON solidarity_posts (sync_status)',
    'CREATE INDEX IF NOT EXISTS idx_services_tenant '
        'ON local_services (tenant_id, is_deleted, category)',
    'CREATE INDEX IF NOT EXISTS idx_services_sync '
        'ON local_services (sync_status)',
    'CREATE INDEX IF NOT EXISTS idx_outbox_tenant '
        'ON sync_outbox (tenant_id, outbox_id)',
  ];

  /// Pedidos de ayuda (SOS). Se guardan al instante sin red (Sprint 8).
  static const createVulnerableReports = '''
    CREATE TABLE IF NOT EXISTS vulnerable_reports (
      id TEXT PRIMARY KEY,
      tenant_id TEXT NOT NULL,
      reporter_user_id TEXT NOT NULL,
      urgency_level TEXT NOT NULL,
      vulnerability_type TEXT NOT NULL,
      description TEXT NOT NULL,
      lat REAL NOT NULL,
      lng REAL NOT NULL,
      status TEXT NOT NULL DEFAULT 'PENDIENTE_APOYO',
      helper_user_id TEXT,
      is_deleted INTEGER NOT NULL DEFAULT 0,
      updated_at TEXT NOT NULL,
      sync_status TEXT NOT NULL DEFAULT 'SYNCED'
    )
  ''';

  static const indexesV4 = [
    'CREATE INDEX IF NOT EXISTS idx_reports_tenant '
        'ON vulnerable_reports (tenant_id, is_deleted, status)',
  ];

  /// Grupos de apoyo del barrio (Sprint 11). Solo bajada: los registra la
  /// junta en el servidor y el teléfono los guarda para verlos sin internet.
  static const createSupportGroups = '''
    CREATE TABLE IF NOT EXISTS support_groups (
      id TEXT PRIMARY KEY,
      tenant_id TEXT NOT NULL,
      name TEXT NOT NULL,
      group_type TEXT NOT NULL,
      description TEXT,
      contact_phone TEXT,
      meeting_point TEXT,
      lat REAL,
      lng REAL,
      coordinator_user_id TEXT,
      is_active INTEGER NOT NULL DEFAULT 1,
      is_deleted INTEGER NOT NULL DEFAULT 0,
      updated_at TEXT NOT NULL,
      sync_status TEXT NOT NULL DEFAULT 'SYNCED'
    )
  ''';

  static const indexesV5 = [
    'CREATE INDEX IF NOT EXISTS idx_support_groups_tenant '
        'ON support_groups (tenant_id, is_deleted, is_active)',
  ];

  static const indexesV3 = [
    'CREATE INDEX IF NOT EXISTS idx_endorsements_service '
        'ON neighbor_endorsements (tenant_id, service_id, is_deleted)',
    'CREATE INDEX IF NOT EXISTS idx_users_tenant ON users (tenant_id)',
  ];

  /// Esquema completo para una instalación nueva.
  static const List<String> createAll = [
    createSolidarityPosts,
    createLocalServices,
    createNeighborEndorsements,
    createUsers,
    createSyncOutbox,
    createSyncState,
    createAppSettings,
    createVulnerableReports,
    createSupportGroups,
    createPostPhotos,
    createServicePhotos,
    ...indexes,
    ...indexesV3,
    ...indexesV4,
    ...indexesV5,
  ];

  /// Pasos de actualización: clave = versión destino.
  /// v1 (Sprint 1): solidarity_posts, sync_outbox, sync_state.
  /// v2 (Sprint 2): + local_services + índices.
  /// v3 (Sprint 5): + neighbor_endorsements, users, app_settings.
  /// v4 (Sprint 8): + vulnerable_reports (SOS sin red).
  /// v5 (Sprint 11): + support_groups (grupos de apoyo sin red).
  /// v6 (Sprint 12): + users.email_contacto (correo de contacto del perfil).
  /// v7 (Sprint 12): + local_services.contact_phone / contact_whatsapp
  ///     (contacto del comerciante; lo manda el servidor en el pull).
  /// v8 (Sprint 13): favores con autor, contacto, foto y coordinador + post_photos.
  /// v9 (Sprint 13): servicios con precio y fotos (service_photos); reseñas con nombre.
  static const Map<int, List<String>> migrations = {
    2: [createLocalServices, ...indexes],
    3: [
      createNeighborEndorsements,
      createUsers,
      createAppSettings,
      ...indexesV3,
    ],
    4: [createVulnerableReports, ...indexesV4],
    5: [createSupportGroups, ...indexesV5],
    // v7: los servicios ya descargados no traían el contacto del comerciante.
    // El pull es incremental y nunca los volvería a bajar: se olvida el cursor
    // para descargar todo UNA vez (lo pendiente de subir no se pisa).
    7: ['DELETE FROM sync_state'],
    // v8: favores con autor, contacto, foto y quién ayuda. Se baja todo de
    // nuevo UNA vez para completar los favores ya guardados.
    8: [createPostPhotos, 'DELETE FROM sync_state'],
    // v9: servicios con precio y fotos; reseñas con el nombre de quien califica.
    9: [createServicePhotos, 'DELETE FROM sync_state'],
  };

  /// Columnas nuevas en tablas existentes, por versión destino.
  /// Se agregan solo si faltan (SQLite no tiene ADD COLUMN IF NOT EXISTS).
  static const Map<int, Map<String, Map<String, String>>> addedColumns = {
    3: {
      'local_services': {
        'rating_avg': 'REAL',
        'publisher_type': 'TEXT',
        'publisher_name': 'TEXT',
      },
    },
    6: {
      'users': {'email_contacto': 'TEXT'},
    },
    7: {
      'local_services': {'contact_phone': 'TEXT', 'contact_whatsapp': 'TEXT'},
    },
    8: {
      'solidarity_posts': {
        'author_name': 'TEXT',
        'contact_phone': 'TEXT',
        'contact_whatsapp': 'TEXT',
        'has_photo': 'INTEGER NOT NULL DEFAULT 0',
        'coordinator_user_id': 'TEXT',
        'coordinator_name': 'TEXT',
      },
    },
    9: {
      'local_services': {
        'price_text': 'TEXT',
        'photo_count': 'INTEGER NOT NULL DEFAULT 0',
      },
      'neighbor_endorsements': {'endorser_name': 'TEXT'},
    },
  };
}
