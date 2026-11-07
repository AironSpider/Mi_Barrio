import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import '../auth/auth_session_store.dart';
import '../database_sqlite/sqlite_database.dart';
import '../database_sqlite/sync_outbox_dao.dart';

/// Resultado de subir los cambios pendientes.
class PushResult {
  final bool success;
  final int sentCount;
  final int processedCount;
  final String? message;

  const PushResult({
    required this.success,
    this.sentCount = 0,
    this.processedCount = 0,
    this.message,
  });
}

/// Resultado de descargar cambios del servidor.
class PullResult {
  final bool success;
  final int savedCount;
  final int skippedPendingCount;
  final String? message;

  const PullResult({
    required this.success,
    this.savedCount = 0,
    this.skippedPendingCount = 0,
    this.message,
  });
}

class SyncWorker {
  final String baseUrl;
  final SyncOutboxDao _outboxDao = SyncOutboxDao();
  final http.Client _client;

  // Solo estas tablas se pueden marcar como SYNCED.
  static const _syncableTables = {
    'solidarity_posts',
    'local_services',
    'neighbor_endorsements',
    'users',
  };

  /// Columnas que se guardan en SQLite por tabla al hacer pull.
  /// Lo que el servidor mande de más (ej. created_at) se ignora;
  /// lo que falte queda en null / valor por defecto.
  static const _pullColumns = <String, List<String>>{
    'solidarity_posts': [
      'id',
      'tenant_id',
      'author_user_id',
      'flow_type',
      'modality',
      'title',
      'description',
      'is_emergency_context',
      'status',
      'lat',
      'lng',
      'is_deleted',
      'updated_at',
    ],
    'local_services': [
      'id',
      'tenant_id',
      'provider_user_id',
      'category',
      'title',
      'description',
      'is_available_in_emergency',
      'endorsements_count',
      'rating_avg',
      'publisher_type',
      'publisher_name',
      'lat',
      'lng',
      'is_deleted',
      'updated_at',
    ],
  };

  /// Columnas booleanas: el servidor manda true/false, SQLite guarda 1/0.
  static const _boolColumns = {
    'is_emergency_context',
    'is_available_in_emergency',
    'is_deleted',
  };

  SyncWorker({required this.baseUrl, http.Client? client})
    : _client = client ?? http.Client();

  Future<void> synchronize(String tenantId) async {
    await pushLocalChanges(tenantId);
    await pullRemoteChanges(tenantId);
  }

  Future<PushResult> pushLocalChanges(String tenantId) async {
    try {
      final pending = await _outboxDao.getPendingMutations(tenantId);
      if (pending.isEmpty) {
        return const PushResult(success: true, message: 'Nada pendiente');
      }

      final mutations = pending.map((item) {
        return {
          'target_table': item['target_table'],
          'record_id': item['record_id'],
          'operation': item['operation'],
          'payload': jsonDecode(item['payload_json'] as String),
        };
      }).toList();

      final response = await _client
          .post(
            Uri.parse('$baseUrl/api/v1/sync/push'),
            headers: {
              'Content-Type': 'application/json',
              'X-Tenant-ID': tenantId,
              if (AuthSessionStore.instance.token case final token?)
                'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'client_sync_timestamp': DateTime.now().toUtc().toIso8601String(),
              'mutations': mutations,
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        return PushResult(
          success: false,
          sentCount: pending.length,
          message: 'El servidor respondio ${response.statusCode}',
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final confirmed = ((data['processed_record_ids'] as List?) ?? [])
          .map((e) => e.toString())
          .toSet();
      final rejected = ((data['rejected'] as List?) ?? const [])
          .whereType<Map>()
          .map((item) => item['reason']?.toString())
          .whereType<String>()
          .where((reason) => reason.isNotEmpty)
          .toList(growable: false);

      // Solo lo que el servidor confirmo.
      final toClean = pending
          .where((m) => confirmed.contains(m['record_id']))
          .toList();

      final db = await LocalDatabase.instance.database;
      await db.transaction((txn) async {
        for (final m in toClean) {
          final recordId = m['record_id'] as String;
          final table = m['target_table'] as String;

          // 1. Sacar de la cola esa mutacion exacta.
          await txn.delete(
            'sync_outbox',
            where: 'outbox_id = ?',
            whereArgs: [m['outbox_id']],
          );

          // 2. Marcar SYNCED solo si ya no quedan cambios nuevos del mismo registro.
          final remaining = await txn.query(
            'sync_outbox',
            where: 'tenant_id = ? AND record_id = ?',
            whereArgs: [tenantId, recordId],
            limit: 1,
          );
          if (remaining.isEmpty && _syncableTables.contains(table)) {
            await txn.update(
              table,
              {'sync_status': 'SYNCED'},
              where: 'id = ?',
              whereArgs: [recordId],
            );
          }
        }
      });

      return PushResult(
        success: toClean.length == pending.length,
        sentCount: pending.length,
        processedCount: toClean.length,
        message: toClean.length == pending.length
            ? null
            : rejected.isNotEmpty
            ? 'El servidor rechazó ${pending.length - toClean.length} cambio(s): ${rejected.join('; ')}'
            : 'El servidor no confirmó ${pending.length - toClean.length} cambio(s)',
      );
    } catch (e) {
      // Sin internet o timeout: los datos locales quedan intactos.
      return PushResult(success: false, message: e.toString());
    }
  }

  /// Descarga lo que cambió en el servidor desde la última vez y lo guarda en SQLite.
  ///
  /// Si un registro tiene cambios locales todavía sin subir (PENDING), NO se pisa:
  /// primero se sube con el push y el servidor decide con Last-Write-Wins.
  Future<PullResult> pullRemoteChanges(String tenantId) async {
    try {
      final db = await LocalDatabase.instance.database;

      final state = await db.query(
        'sync_state',
        where: 'tenant_id = ?',
        whereArgs: [tenantId],
      );
      final lastPulled = state.isNotEmpty
          ? state.first['last_pulled_at'] as String?
          : null;

      final uri = Uri.parse('$baseUrl/api/v1/sync/pull').replace(
        queryParameters: lastPulled != null ? {'since': lastPulled} : null,
      );

      final response = await _client
          .get(
            uri,
            headers: {
              'X-Tenant-ID': tenantId,
              if (AuthSessionStore.instance.token case final token?)
                'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        return PullResult(
          success: false,
          message: 'El servidor respondio ${response.statusCode}',
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final serverTimestamp = data['server_timestamp'] as String;
      final delta = (data['delta'] as Map<String, dynamic>?) ?? const {};

      var saved = 0;
      var skipped = 0;
      await db.transaction((txn) async {
        for (final entry in _pullColumns.entries) {
          final table = entry.key;
          final rows = (delta[table] as List?) ?? const [];
          if (rows.isEmpty) continue;

          final pendingIds = (await txn.query(
            table,
            columns: ['id'],
            where: 'tenant_id = ? AND sync_status = ?',
            whereArgs: [tenantId, 'PENDING'],
          )).map((r) => r['id']).toSet();

          for (final raw in rows) {
            final record = raw as Map<String, dynamic>;
            // Seguridad multi-tenant: nunca guardar datos de otro barrio.
            if (record['tenant_id'] != null &&
                record['tenant_id'] != tenantId) {
              continue;
            }
            if (pendingIds.contains(record['id'])) {
              skipped++;
              continue;
            }
            final row = <String, Object?>{'tenant_id': tenantId};
            for (final col in entry.value) {
              if (!record.containsKey(col)) continue;
              final value = record[col];
              row[col] = _boolColumns.contains(col)
                  ? ((value == true || value == 1) ? 1 : 0)
                  : value;
            }
            row['sync_status'] = 'SYNCED';
            await txn.insert(
              table,
              row,
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
            saved++;
          }
        }

        await txn.insert('sync_state', {
          'tenant_id': tenantId,
          'last_pulled_at': serverTimestamp,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      });

      return PullResult(
        success: true,
        savedCount: saved,
        skippedPendingCount: skipped,
      );
    } catch (e) {
      // Sin conexion: el usuario sigue usando sus datos locales sin error.
      return PullResult(success: false, message: e.toString());
    }
  }
}
