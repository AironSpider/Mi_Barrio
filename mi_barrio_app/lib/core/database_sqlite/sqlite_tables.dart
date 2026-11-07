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
  static const int schemaVersion = 2;

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
      sync_status TEXT NOT NULL DEFAULT 'SYNCED'
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
      lat REAL NOT NULL,
      lng REAL NOT NULL,
      is_deleted INTEGER NOT NULL DEFAULT 0,
      updated_at TEXT NOT NULL,
      sync_status TEXT NOT NULL DEFAULT 'SYNCED'
    )
  ''';

  // ── Tablas exclusivas del dispositivo ──

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

  /// Esquema completo para una instalación nueva.
  static const List<String> createAll = [
    createSolidarityPosts,
    createLocalServices,
    createSyncOutbox,
    createSyncState,
    ...indexes,
  ];

  /// Pasos de actualización: clave = versión destino.
  /// v1 (Sprint 1): solidarity_posts, sync_outbox, sync_state.
  /// v2 (Sprint 2): + local_services + índices.
  static const Map<int, List<String>> migrations = {
    2: [createLocalServices, ...indexes],
  };
}
