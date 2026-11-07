import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import '../database_sqlite/sqlite_database.dart';
import '../database_sqlite/sync_outbox_dao.dart';

class SyncWorker {
  final String baseUrl;
  final SyncOutboxDao _outboxDao = SyncOutboxDao();

  SyncWorker({required this.baseUrl});

  Future<void> synchronize(String tenantId) async {
    await pushLocalChanges(tenantId);
    await pullRemoteChanges(tenantId);
  }

  Future<void> pushLocalChanges(String tenantId) async {
    final pending = await _outboxDao.getPendingMutations(tenantId);
    if (pending.isEmpty) return;

    final mutationsList = pending.map((item) {
      return {
        'target_table': item['target_table'],
        'record_id': item['record_id'],
        'operation': item['operation'],
        'payload': jsonDecode(item['payload_json'] as String),
      };
    }).toList();

    final body = jsonEncode({
      'client_sync_timestamp': DateTime.now().toUtc().toIso8601String(),
      'mutations': mutationsList,
    });

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/v1/sync/push'),
        headers: {
          'Content-Type': 'application/json',
          'X-Tenant-ID': tenantId,
        },
        body: body,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> processedIds = data['processed_record_ids'] ?? [];
        final ids = processedIds.cast<String>();

        // 1. Quitar elementos enviados de la cola
        await _outboxDao.removeProcessed(ids);

        // 2. Marcar en la tabla local como SYNCED
        final db = await LocalDatabase.instance.database;
        for (var id in ids) {
          await db.update(
            'solidarity_posts',
            {'sync_status': 'SYNCED'},
            where: 'id = ?',
            whereArgs: [id],
          );
        }
      }
    } catch (e) {
      // Sin internet: falla silenciosamente y mantiene los datos locales intactos
    }
  }

  Future<void> pullRemoteChanges(String tenantId) async {
    final db = await LocalDatabase.instance.database;

    final state = await db.query(
      'sync_state',
      where: 'tenant_id = ?',
      whereArgs: [tenantId],
    );

    String? lastPulled = state.isNotEmpty ? state.first['last_pulled_at'] as String? : null;

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
      // Sin conexión: el usuario sigue consumiendo sus datos locales sin error
    }
  }
}