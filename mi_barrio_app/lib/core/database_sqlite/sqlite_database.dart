import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class LocalDatabase {
  static final LocalDatabase instance = LocalDatabase._init();
  static Database? _database;

  LocalDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('mi_barrio_offline.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    // 1. Tabla espejo de solidaridad con columna local sync_status
    await db.execute('''
      CREATE TABLE solidarity_posts (
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
    ''');

    // 2. Cola Outbox: almacena mutaciones pendientes de subir
    await db.execute('''
      CREATE TABLE sync_outbox (
        outbox_id INTEGER PRIMARY KEY AUTOINCREMENT,
        tenant_id TEXT NOT NULL,
        target_table TEXT NOT NULL,
        record_id TEXT NOT NULL,
        operation TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    // 3. Control de última descarga incremental
    await db.execute('''
      CREATE TABLE sync_state (
        tenant_id TEXT PRIMARY KEY,
        last_pulled_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> close() async {
    final db = await instance.database;
    db.close();
  }
}