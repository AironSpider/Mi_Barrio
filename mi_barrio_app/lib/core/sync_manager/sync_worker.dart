import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import '../auth/auth_session_store.dart';
import '../barrio_context/emergency_mode_provider.dart';
import '../database_sqlite/sqlite_database.dart';
import '../database_sqlite/sync_outbox_dao.dart';
import '../network/api_client.dart';

/// Resultado de subir los cambios pendientes.
class PushResult {
  final bool success;
  final int sentCount;
  final int processedCount;
  final String? message;
  final bool unauthorized;

  /// Cuántos envíos a `/sync/push` se hicieron (lotes de [SyncWorker.maxBatch]).
  final int batchCount;

  /// Falla TEMPORAL (servidor caído o lento, sin respuesta): vale la pena
  /// reintentar pronto. Un 401 o un dato rechazado no se arreglan reintentando.
  final bool retryable;

  const PushResult({
    required this.success,
    this.sentCount = 0,
    this.processedCount = 0,
    this.message,
    this.unauthorized = false,
    this.batchCount = 0,
    this.retryable = false,
  });
}

/// Resultado interno de un lote.
class _BatchOutcome {
  const _BatchOutcome({
    required this.sentCount,
    this.processedCount = 0,
    this.message,
    this.httpFailed = false,
    this.unauthorized = false,
    this.retryable = false,
  });

  final int sentCount;
  final int processedCount;
  final String? message;

  /// El servidor no respondió 200: se detienen los lotes siguientes.
  final bool httpFailed;
  final bool unauthorized;
  final bool retryable;
}

/// Resultado de descargar cambios del servidor.
class PullResult {
  final bool success;
  final int savedCount;
  final int skippedPendingCount;
  final String? message;
  final bool unauthorized;

  /// Ver [PushResult.retryable].
  final bool retryable;

  const PullResult({
    required this.success,
    this.savedCount = 0,
    this.skippedPendingCount = 0,
    this.message,
    this.unauthorized = false,
    this.retryable = false,
  });
}

/// Respuestas HTTP que suelen arreglarse solas: 408 (tiempo agotado),
/// 429 (demasiadas peticiones) y 5xx (el servidor falló o se está reiniciando).
bool isTransientHttpStatus(int status) =>
    status == 408 || status == 429 || status >= 500;

class SyncWorker {
  final String baseUrl;
  final SyncOutboxDao _outboxDao = SyncOutboxDao();
  final ApiClient _api;

  // Solo estas tablas se pueden marcar como SYNCED.
  static const _syncableTables = {
    'solidarity_posts',
    'local_services',
    'neighbor_endorsements',
    'users',
    'vulnerable_reports',
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
      // Solo bajada: nombre público y contacto del autor, foto y quién ayuda.
      'author_name',
      'contact_phone',
      'contact_whatsapp',
      'has_photo',
      'coordinator_user_id',
      'coordinator_name',
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
      'contact_phone', // contacto del comerciante (solo bajada)
      'contact_whatsapp',
      'price_text',
      'photo_count', // las fotos se piden aparte (solo bajada)
      'lat',
      'lng',
      'is_deleted',
      'updated_at',
    ],
    'vulnerable_reports': [
      'id',
      'tenant_id',
      'reporter_user_id',
      'urgency_level',
      'vulnerability_type',
      'description',
      'lat',
      'lng',
      'status',
      'helper_user_id',
      'is_deleted',
      'updated_at',
    ],
    // Solo bajada (Sprint 11): los registra la junta en el servidor.
    'support_groups': [
      'id',
      'tenant_id',
      'name',
      'group_type',
      'description',
      'contact_phone',
      'meeting_point',
      'lat',
      'lng',
      'coordinator_user_id',
      'is_active',
      'is_deleted',
      'updated_at',
    ],
  };

  /// Columnas booleanas: el servidor manda true/false, SQLite guarda 1/0.
  static const _boolColumns = {
    'is_emergency_context',
    'is_available_in_emergency',
    'is_deleted',
    'is_active',
    'has_photo',
  };

  SyncWorker({required this.baseUrl, http.Client? client})
    : _api = ApiClient(baseUrl: baseUrl, client: client);

  /// Máximo de cambios por envío que acepta `/sync/push` (si se pasa: 413).
  static const maxBatch = 200;

  /// Sube la cola en orden y en lotes de [maxBatch].
  ///
  /// Cada lote se confirma en SQLite apenas responde el servidor: si se corta
  /// la red a la mitad, lo ya enviado no se repite y el resto queda pendiente.
  /// Si un lote falla (sin red, 401, 5xx) se detiene: los lotes siguientes
  /// esperan al próximo sync para respetar el orden de los cambios.
  Future<PushResult> pushLocalChanges(String tenantId) async {
    var sent = 0;
    var processed = 0;
    var batches = 0;
    final problems = <String>[];
    try {
      final pending = await _outboxDao.getPendingMutations(tenantId);
      if (pending.isEmpty) {
        return const PushResult(success: true, message: 'Nada pendiente');
      }

      for (var start = 0; start < pending.length; start += maxBatch) {
        final end = start + maxBatch < pending.length
            ? start + maxBatch
            : pending.length;
        final batch = await _pushBatch(tenantId, pending.sublist(start, end));
        batches++;
        sent += batch.sentCount;
        processed += batch.processedCount;
        if (batch.message != null) problems.add(batch.message!);
        if (batch.httpFailed) {
          return PushResult(
            success: false,
            sentCount: sent,
            processedCount: processed,
            batchCount: batches,
            message: problems.join(' | '),
            unauthorized: batch.unauthorized,
            retryable: batch.retryable,
          );
        }
      }

      return PushResult(
        success: problems.isEmpty,
        sentCount: sent,
        processedCount: processed,
        batchCount: batches,
        message: problems.isNotEmpty ? problems.join(' | ') : null,
      );
    } catch (e) {
      // Sin internet o timeout: lo que no se confirmó queda intacto en la cola.
      return PushResult(
        success: false,
        sentCount: sent,
        processedCount: processed,
        batchCount: batches,
        message: e.toString(),
        retryable: true,
      );
    }
  }

  /// Envía un lote (≤ [maxBatch]) y limpia de la cola lo confirmado o rechazado.
  Future<_BatchOutcome> _pushBatch(
    String tenantId,
    List<Map<String, dynamic>> pending,
  ) async {
    final mutations = pending.map((item) {
      return {
        'target_table': item['target_table'],
        'record_id': item['record_id'],
        'operation': item['operation'],
        'payload': jsonDecode(item['payload_json'] as String),
      };
    }).toList();

    final response = await _api.post('/api/v1/sync/push', tenantId, {
      'client_sync_timestamp': DateTime.now().toUtc().toIso8601String(),
      'mutations': mutations,
    });

    if (response.statusCode != 200) {
      if (response.statusCode == 401) {
        await AuthSessionStore.instance.invalidate();
      }
      return _BatchOutcome(
        httpFailed: true,
        sentCount: pending.length,
        message: 'El servidor respondio ${response.statusCode}',
        unauthorized: response.statusCode == 401,
        retryable: isTransientHttpStatus(response.statusCode),
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final confirmed = ((data['processed_record_ids'] as List?) ?? [])
        .map((e) => e.toString())
        .toSet();
    final rejectedItems = ((data['rejected'] as List?) ?? const [])
        .whereType<Map>()
        .where(
          (item) =>
              item['record_id'] is String && item['target_table'] is String,
        )
        .toList(growable: false);
    // Un rechazo es definitivo (dato inválido): sale de la cola como "Sin enviar".
    final rejectedReasons = <String, String>{
      for (final item in rejectedItems)
        '${item['target_table']}:${item['record_id']}':
            item['reason']?.toString() ?? 'Rechazado por el servidor',
    };

    // Confirmed changes and terminal rejections are both removed from outbox.
    final toClean = pending
        .where(
          (m) =>
              confirmed.contains(m['record_id']) ||
              rejectedReasons.containsKey(
                '${m['target_table']}:${m['record_id']}',
              ),
        )
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
        final wasRejected = rejectedReasons.containsKey('$table:$recordId');
        if (_syncableTables.contains(table) &&
            (wasRejected || remaining.isEmpty)) {
          await txn.update(
            table,
            {'sync_status': wasRejected ? 'FAILED' : 'SYNCED'},
            where: 'id = ?',
            whereArgs: [recordId],
          );
        }
      }
    });

    return _BatchOutcome(
      sentCount: pending.length,
      processedCount: pending
          .where((m) => confirmed.contains(m['record_id']))
          .length,
      message: rejectedReasons.isNotEmpty
          ? 'El servidor rechazó ${rejectedReasons.length} cambio(s): ${rejectedReasons.values.join('; ')}'
          : toClean.length >= pending.length
          ? null
          : 'El servidor no confirmó ${pending.length - toClean.length} cambio(s)',
    );
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

      final response = await _api.get(
        '/api/v1/sync/pull',
        tenantId,
        query: lastPulled != null ? {'since': lastPulled} : null,
      );

      if (response.statusCode != 200) {
        if (response.statusCode == 401) {
          await AuthSessionStore.instance.invalidate();
        }
        return PullResult(
          success: false,
          message: 'El servidor respondio ${response.statusCode}',
          unauthorized: response.statusCode == 401,
          retryable: isTransientHttpStatus(response.statusCode),
        );
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final serverTimestamp = data['server_timestamp'] as String;
      final delta = (data['delta'] as Map<String, dynamic>?) ?? const {};

      var saved = 0;
      var skipped = 0;
      // Filas del servidor que NO se guardaron porque aquí hay cambios sin subir.
      // El cursor no debe pasar por encima de ellas: si el servidor se queda con
      // su versión (Last-Write-Wins), el próximo pull la tiene que volver a traer.
      DateTime? oldestSkipped;
      var skippedWithoutStamp = false;
      await db.transaction((txn) async {
        for (final entry in _pullColumns.entries) {
          final table = entry.key;
          final rows = (delta[table] as List?) ?? const [];
          if (rows.isEmpty) continue;

          // Solo se protege lo que TODAVÍA está en la cola (se va a subir).
          // Un registro FAILED ya salió de la cola: el servidor lo rechazó, así
          // que su versión es la verdad y se debe ver (antes quedaba congelado
          // para siempre, sin recibir nunca más cambios).
          final pendingIds = (await txn.query(
            'sync_outbox',
            columns: ['record_id'],
            where: 'tenant_id = ? AND target_table = ?',
            whereArgs: [tenantId, table],
          )).map((r) => r['record_id']).toSet();

          for (final raw in rows) {
            final record = raw as Map<String, dynamic>;
            // Seguridad multi-tenant: nunca guardar datos de otro barrio.
            if (record['tenant_id'] != null &&
                record['tenant_id'] != tenantId) {
              continue;
            }
            if (pendingIds.contains(record['id'])) {
              skipped++;
              final stamp = DateTime.tryParse(
                '${record['server_updated_at'] ?? ''}',
              );
              if (stamp == null) {
                skippedWithoutStamp = true;
              } else if (oldestSkipped == null ||
                  stamp.isBefore(oldestSkipped!)) {
                oldestSkipped = stamp;
              }
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

        final cursor = _nextCursor(
          serverTimestamp: serverTimestamp,
          previous: lastPulled,
          oldestSkipped: oldestSkipped,
          skippedWithoutStamp: skippedWithoutStamp,
        );
        if (cursor != null) {
          await txn.insert('sync_state', {
            'tenant_id': tenantId,
            'last_pulled_at': cursor,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });

      // Modo Emergencia decidido por la junta vecinal (llega en cada pull).
      final tenant = data['tenant'];
      if (tenant is Map && tenant['is_emergency_active'] is bool) {
        await EmergencyModeProvider.instance.setTenantFlag(
          tenant['is_emergency_active'] as bool,
          tenantId: tenantId,
        );
      }

      return PullResult(
        success: true,
        savedCount: saved,
        skippedPendingCount: skipped,
      );
    } catch (e) {
      // Sin conexion: el usuario sigue usando sus datos locales sin error.
      return PullResult(success: false, message: e.toString(), retryable: true);
    }
  }

  /// Hasta dónde quedó al día este teléfono.
  /// - Normal: la hora del servidor de este pull.
  /// - Si se saltaron filas por cambios locales sin subir: la hora de la más
  ///   antigua de ellas (el próximo pull la vuelve a traer).
  /// - Si una saltada no trae hora: no se avanza (null = conservar el anterior).
  static String? _nextCursor({
    required String serverTimestamp,
    required String? previous,
    required DateTime? oldestSkipped,
    required bool skippedWithoutStamp,
  }) {
    if (skippedWithoutStamp) return previous;
    final server = DateTime.tryParse(serverTimestamp);
    if (oldestSkipped != null &&
        server != null &&
        oldestSkipped.isBefore(server)) {
      return oldestSkipped.toUtc().toIso8601String();
    }
    return serverTimestamp;
  }
}
