import 'package:sqflite/sqflite.dart';

import '../../../core/database_sqlite/sqlite_database.dart';
import '../../../core/database_sqlite/sqlite_tables.dart';
import '../../../core/database_sqlite/sync_outbox_dao.dart';
import 'user_profile_model.dart';

/// "¿Ya vio el tutorial?" por vecino. El tutorial se muestra solo la primera vez.
///
/// Se guarda en 2 lugares:
/// - `app_settings` (`tutorial_completed:<userId>`): respuesta inmediata y sin
///   red; sobrevive al cierre de sesión (se borra la fila `users`, no esto).
/// - `users.tutorial_completed` + cola de sync: llega al servidor, así en un
///   teléfono nuevo tampoco se repite (lo trae [ProfileSync]).
///
/// Uso en pantalla:
/// ```dart
/// if (!await TutorialProgress().isCompleted(userId)) { /* mostrar tutorial */ }
/// // Al tocar "Empezar" o "Saltar":
/// await TutorialProgress().markCompleted(tenantId: tenantId, userId: userId);
/// ```
class TutorialProgress {
  TutorialProgress({LocalDatabase? database, SyncOutboxDao? outboxDao})
      : _db = database ?? LocalDatabase.instance,
        _outboxDao = outboxDao ?? SyncOutboxDao();

  final LocalDatabase _db;
  final SyncOutboxDao _outboxDao;

  static String _key(String userId) => 'tutorial_completed:$userId';

  /// true si este vecino ya terminó (o saltó) el tutorial en este teléfono
  /// o en otro (dato que bajó del servidor).
  Future<bool> isCompleted(String userId) async {
    final db = await _db.database;
    if (await _localFlag(db, userId)) return true;
    final rows = await db.query(
      UserProfileModel.table,
      columns: ['tutorial_completed'],
      where: 'id = ? AND is_deleted = 0',
      whereArgs: [userId],
      limit: 1,
    );
    return rows.isNotEmpty && rows.first['tutorial_completed'] == 1;
  }

  /// Marca el tutorial como visto. Funciona sin internet: queda en el teléfono
  /// al instante y se envía al servidor en el próximo sync. Llamarlo 2 veces
  /// no encola nada nuevo.
  Future<void> markCompleted({
    required String tenantId,
    required String userId,
  }) async {
    final db = await _db.database;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.transaction((txn) async {
      final alreadyLocal = await _localFlag(txn, userId);
      final rows = await txn.query(
        UserProfileModel.table,
        columns: ['tutorial_completed'],
        where: 'id = ?',
        whereArgs: [userId],
        limit: 1,
      );
      final rowDone = rows.isNotEmpty && rows.first['tutorial_completed'] == 1;
      if (alreadyLocal && (rows.isEmpty || rowDone)) return;

      await txn.insert('app_settings', {'key': _key(userId), 'value': '1'},
          conflictAlgorithm: ConflictAlgorithm.replace);
      if (rows.isNotEmpty && !rowDone) {
        await txn.update(
          UserProfileModel.table,
          {
            'tutorial_completed': 1,
            'updated_at': now,
            'sync_status': SqliteTables.syncPending,
          },
          where: 'id = ?',
          whereArgs: [userId],
        );
      }
      await queueServerUpdate(txn, tenantId: tenantId, userId: userId, updatedAt: now);
    });
  }

  /// Envía SOLO la bandera al servidor (update parcial: el servidor cambia
  /// únicamente los campos que llegan, así no se pisa el teléfono ni el nombre).
  Future<void> queueServerUpdate(
    DatabaseExecutor executor, {
    required String tenantId,
    required String userId,
    required String updatedAt,
  }) =>
      _outboxDao.queueMutation(
        tenantId: tenantId,
        targetTable: UserProfileModel.table,
        recordId: userId,
        operation: OutboxOperation.upsert,
        payload: {'id': userId, 'tutorial_completed': true, 'updated_at': updatedAt},
        executor: executor,
      );

  /// Solo la bandera local (sin mirar el perfil).
  Future<bool> localFlag(String userId) async => _localFlag(await _db.database, userId);

  /// Guarda la bandera local sin encolar nada (cuando ya viene del servidor).
  Future<void> rememberLocally(DatabaseExecutor executor, String userId) => executor.insert(
        'app_settings',
        {'key': _key(userId), 'value': '1'},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  /// Igual que [localFlag], pero dentro de una transacción ya abierta
  /// (sqflite se bloquea si se consulta la base fuera de la transacción).
  static Future<bool> localFlagIn(DatabaseExecutor executor, String userId) =>
      _localFlag(executor, userId);

  static Future<bool> _localFlag(DatabaseExecutor db, String userId) async {
    final rows = await db.query('app_settings',
        columns: ['value'], where: 'key = ?', whereArgs: [_key(userId)], limit: 1);
    return rows.isNotEmpty && rows.first['value'] == '1';
  }
}
