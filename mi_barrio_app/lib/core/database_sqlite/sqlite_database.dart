import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import 'sqlite_tables.dart';

/// Instancia única de la base de datos local `mi_barrio_offline.db`.
///
/// Es el motor primario de la app (Local-First): la UI lee y escribe aquí
/// siempre, con o sin internet.
class LocalDatabase {
  static final LocalDatabase instance = LocalDatabase._init();
  static const fileName = 'mi_barrio_offline.db';

  Database? _database;
  Future<Database>? _opening;
  String? _pathOverride;

  LocalDatabase._init();

  /// Abre la base una sola vez, aunque varias pantallas la pidan a la vez.
  Future<Database> get database {
    final db = _database;
    if (db != null && db.isOpen) return Future.value(db);
    return _opening ??= _open().then((opened) {
      _database = opened;
      _opening = null;
      return opened;
    }, onError: (Object error, StackTrace stack) {
      _opening = null;
      Error.throwWithStackTrace(error, stack);
    });
  }

  Future<Database> _open() async {
    final path = _pathOverride ?? join(await getDatabasesPath(), fileName);
    return openDatabase(
      path,
      version: SqliteTables.schemaVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    final batch = db.batch();
    for (final sql in SqliteTables.createAll) {
      batch.execute(sql);
    }
    await batch.commit(noResult: true);
  }

  /// Actualiza teléfonos que ya tenían una versión anterior instalada
  /// sin borrar sus datos ni sus mutaciones pendientes.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    for (var v = oldVersion + 1; v <= newVersion; v++) {
      for (final sql in SqliteTables.migrations[v] ?? const <String>[]) {
        await db.execute(sql);
      }
      final columns = SqliteTables.addedColumns[v] ?? const {};
      for (final table in columns.entries) {
        final existing = (await db.rawQuery('PRAGMA table_info(${table.key})'))
            .map((c) => c['name'])
            .toSet();
        for (final col in table.value.entries) {
          if (!existing.contains(col.key)) {
            await db.execute('ALTER TABLE ${table.key} ADD COLUMN ${col.key} ${col.value}');
          }
        }
      }
    }
  }

  Future<void> close() async {
    final db = _database;
    _database = null;
    _opening = null;
    if (db != null && db.isOpen) await db.close();
  }

  /// Solo para tests: cierra la base actual y usa otra ruta
  /// (por ejemplo `inMemoryDatabasePath`).
  @visibleForTesting
  Future<void> resetForTesting({String? path}) async {
    await close();
    _pathOverride = path;
  }
}
