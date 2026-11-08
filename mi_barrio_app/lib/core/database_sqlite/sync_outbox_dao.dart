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

  /// Cantidad de registros con cambios sin subir en el barrio (para el aviso
  /// "Tienes N cambios sin sincronizar"). Editar 3 veces el mismo favor cuenta 1.
  Future<int> countPending(String tenantId) async {
    final db = await _dbProvider.database;
    final r = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM '
      '(SELECT DISTINCT target_table, record_id FROM sync_outbox WHERE tenant_id = ?)',
      [tenantId],
    );
    return (r.first['c'] as int?) ?? 0;
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

  static const _ownerKey = 'pending_outbox_owner';

  /// Recuerda de quién son los cambios pendientes cuando la sesión vence sin
  /// cerrar sesión a propósito: si vuelve a entrar la MISMA persona, se suben.
  Future<void> rememberPendingOwner({
    required String tenantId,
    required String userId,
  }) async {
    final db = await _dbProvider.database;
    await db.insert('app_settings', {
      'key': _ownerKey,
      'value': '$tenantId|$userId',
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<({String tenantId, String userId})?> readPendingOwner() async {
    final db = await _dbProvider.database;
    final rows = await db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: [_ownerKey],
      limit: 1,
    );
    final value = rows.isEmpty ? null : rows.first['value'] as String?;
    final parts = value?.split('|');
    if (parts == null || parts.length != 2) return null;
    return (tenantId: parts[0], userId: parts[1]);
  }

  Future<void> forgetPendingOwner() async {
    final db = await _dbProvider.database;
    await db.delete('app_settings', where: 'key = ?', whereArgs: [_ownerKey]);
  }

  /// Al cerrar sesión (o al entrar otra persona): borra lo PRIVADO de la cuenta.
  ///
  /// - El perfil (`users`) se borra siempre.
  /// - De favores, servicios, calificaciones y SOS se borra solo lo que NUNCA
  ///   llegó al servidor (PENDING / FAILED). Lo ya publicado (SYNCED) es del
  ///   barrio y se queda: el pull es incremental y no lo volvería a bajar,
  ///   así que el siguiente vecino de este teléfono dejaría de verlo.
  /// - La cola del barrio se vacía (lo pendiente era de esta cuenta).
  Future<void> clearUserData({
    required String tenantId,
    required String userId,
  }) async {
    final db = await _dbProvider.database;
    const ownerColumns = <String, String>{
      'solidarity_posts': 'author_user_id',
      'local_services': 'provider_user_id',
      'neighbor_endorsements': 'endorser_user_id',
      'vulnerable_reports': 'reporter_user_id',
      'users': 'id',
    };
    const alwaysPrivate = {'users'};

    await db.transaction((txn) async {
      final ownedRecordIds = <String>{};
      for (final entry in ownerColumns.entries) {
        final onlyUnsent = !alwaysPrivate.contains(entry.key);
        final rows = await txn.query(
          entry.key,
          columns: ['id'],
          where: 'tenant_id = ? AND ${entry.value} = ?'
              '${onlyUnsent ? " AND sync_status != 'SYNCED'" : ''}',
          whereArgs: [tenantId, userId],
        );
        final ids = rows.map((row) => row['id'] as String).toSet();
        ownedRecordIds.addAll(ids);
        if (ids.isNotEmpty) {
          final placeholders = List.filled(ids.length, '?').join(',');
          await txn.delete(
            entry.key,
            where: 'id IN ($placeholders)',
            whereArgs: ids.toList(),
          );
        }
      }

      await txn.delete(
        'sync_outbox',
        where: 'tenant_id = ?',
        whereArgs: [tenantId],
      );
    });
  }
}
