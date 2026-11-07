import 'dart:async';
import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import 'sqlite_database.dart';

/// Operaciones permitidas en la cola (contrato del endpoint /sync/push).
class OutboxOperation {
  OutboxOperation._();
  static const upsert = 'UPSERT';
  static const delete = 'DELETE';
  static const values = {upsert, delete};
}

class SyncOutboxDao {
  final LocalDatabase _dbProvider = LocalDatabase.instance;

  static final StreamController<String> _queued = StreamController.broadcast();

  /// Avisa (con el tenant) cada vez que se encola una mutación.
  /// El SyncCoordinator lo escucha para sincronizar apenas haya red.
  static Stream<String> get onQueued => _queued.stream;

  /// Cantidad de mutaciones pendientes del barrio (para el aviso de "N cambios sin sincronizar").
  Future<int> countPending(String tenantId) async {
    final db = await _dbProvider.database;
    final r = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM sync_outbox WHERE tenant_id = ?', [tenantId]);
    return r.first['c'] as int;
  }

  /// Encola una mutación pendiente de subir.
  ///
  /// Pasa [executor] (una transacción) para que el registro y su entrada en la
  /// cola se guarden juntos: si la app se cierra a la mitad, no queda un
  /// registro PENDING sin su mutación (ni al revés).
  Future<void> queueMutation({
    required String tenantId,
    required String targetTable,
    required String recordId,
    required String operation,
    required Map<String, dynamic> payload,
    DatabaseExecutor? executor,
  }) async {
    if (!OutboxOperation.values.contains(operation)) {
      throw ArgumentError.value(operation, 'operation', 'Debe ser UPSERT o DELETE');
    }
    final db = executor ?? await _dbProvider.database;
    await db.insert(
      'sync_outbox',
      {
        'tenant_id': tenantId,
        'target_table': targetTable,
        'record_id': recordId,
        'operation': operation,
        'payload_json': jsonEncode(payload),
        'created_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    // Aviso diferido: si estamos dentro de una transacción, el sync espera a que termine.
    scheduleMicrotask(() => _queued.add(tenantId));
  }

  Future<List<Map<String, dynamic>>> getPendingMutations(String tenantId) async {
    final db = await _dbProvider.database;
    return await db.query(
      'sync_outbox',
      where: 'tenant_id = ?',
      whereArgs: [tenantId],
      orderBy: 'outbox_id ASC',
    );
  }

  Future<void> removeProcessed(List<String> recordIds) async {
    if (recordIds.isEmpty) return;
    final db = await _dbProvider.database;
    final placeholders = List.filled(recordIds.length, '?').join(',');
    await db.delete(
      'sync_outbox',
      where: 'record_id IN ($placeholders)',
      whereArgs: recordIds,
    );
  }
}
