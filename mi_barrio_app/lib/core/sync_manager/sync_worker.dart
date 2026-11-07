import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
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

class SyncWorker {
  final String baseUrl;
  final SyncOutboxDao _outboxDao = SyncOutboxDao();

  // Solo estas tablas se pueden marcar como SYNCED.
  static const _syncableTables = {'solidarity_posts', 'local_services'};

  SyncWorker({required this.baseUrl});

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

      final response = await http
          .post(
            Uri.parse('$baseUrl/api/v1/sync/push'),
            headers: {
              'Content-Type': 'application/json',
              'X-Tenant-ID': tenantId,
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

      // Solo lo que el servidor confirmo.
      final toClean =
          pending.where((m) => confirmed.contains(m['record_id'])).toList();

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
        success: true,
        sentCount: pending.length,
        processedCount: toClean.length,
      );
    } catch (e) {
      // Sin internet o timeout: los datos locales quedan intactos.
      return PushResult(success: false, message: e.toString());
    }
  }

  Future<void> pullRemoteChanges(String tenantId) async {
    final db = await LocalDatabase.instance.database;

    final state = await db.query(
      'sync_state',
      where: 'tenant_id = ?',
      whereArgs: [tenantId],
    );

    String? lastPulled =
        state.isNotEmpty ? state.first['last_pulled_at'] as String? : null;

    final uri = Uri.parse('$baseUrl/api/v1/sync/pull').replace(
      queryParameters: lastPulled != null ? {'since': lastPulled} : null,
    );

    try {
      final response = await http.get(
        uri,
        headers: {'X-Tenant-ID': tenantId},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final String serverTimestamp = data['server_timestamp'];
        final List posts = data['delta']['solidarity_posts'] ?? [];

        final batch = db.batch();
        for (var p in posts) {
          batch.insert(
            'solidarity_posts',
            {
              'id': p['id'],
              'tenant_id': p['tenant_id'],
              'author_user_id': p['author_user_id'],
              'flow_type': p['flow_type'],
              'modality': p['modality'],
              'title': p['title'],
              'description': p['description'],
              'is_emergency_context': p['is_emergency_context'] == true ? 1 : 0,
              'status': p['status'],
              'lat': p['lat'],
              'lng': p['lng'],
              'is_deleted': p['is_deleted'] == true ? 1 : 0,
              'updated_at': p['updated_at'],
              'sync_status': 'SYNCED',
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }

        batch.insert(
          'sync_state',
          {'tenant_id': tenantId, 'last_pulled_at': serverTimestamp},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        await batch.commit(noResult: true);
      }
    } catch (e) {
      // Sin conexion: el usuario sigue usando sus datos locales sin error.
    }
  }
}