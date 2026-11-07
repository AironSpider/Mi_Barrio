import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mi_barrio_app/core/database_sqlite/sqlite_database.dart';
import 'package:mi_barrio_app/core/database_sqlite/sync_outbox_dao.dart';
import 'package:mi_barrio_app/core/sync_manager/pending_changes.dart';
import 'package:mi_barrio_app/core/sync_manager/sync_worker.dart';
import 'package:mi_barrio_app/features/solidarity_network/data/datasources/solidarity_sqlite_ds.dart';
import 'package:mi_barrio_app/features/solidarity_network/data/models/solidarity_post_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Sprint 9 · Dev 2: el servidor acepta máx. 200 cambios por envío (413 si no).
void main() {
  const tenant = 'a1b2c3d4-e5f6-4a8b-9c0d-1e2f3a4b5c6d';
  const otherTenant = 'b2c3d4e5-f6a7-4b8c-9d0e-2f3a4b5c6d7e';
  const me = '5f3a2c1b-1234-4abc-9def-0123456789ab';

  final local = LocalDatabase.instance;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
  });
  setUp(() => local.resetForTesting(path: inMemoryDatabasePath));
  tearDown(() => local.close());

  Future<Database> db() => local.database;

  /// Publica [n] favores sin internet (cada uno deja 1 cambio en la cola).
  Future<List<String>> publishMany(int n, {String tenantId = tenant}) async {
    final ds = SolidaritySqliteDatasource();
    final ids = <String>[];
    for (var i = 0; i < n; i++) {
      final p = await ds.publishInThreeClicks(
        tenantId: tenantId,
        authorUserId: me,
        modality: SolidarityModality.prestamoHerramienta,
        title: 'Favor $i',
        lat: -5.1945,
        lng: -80.6328,
      );
      ids.add(p.id);
    }
    return ids;
  }

  /// Simula el backend real: 413 si llegan más de 200; si no, confirma todo.
  /// [failOnRequest] (1, 2, ...) responde [failStatus] en ese envío.
  ({MockClient client, List<List<String>> requests, List<int> statuses})
      fakeServer({int? failOnRequest, int failStatus = 500, bool throwInstead = false}) {
    final requests = <List<String>>[];
    final statuses = <int>[];
    final client = MockClient((req) async {
      expect(req.url.path, '/api/v1/sync/push');
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      final recordIds = [
        for (final m in body['mutations'] as List) (m as Map)['record_id'] as String,
      ];
      requests.add(recordIds);
      if (requests.length == failOnRequest) {
        if (throwInstead) throw const SocketException('Sin señal');
        statuses.add(failStatus);
        return http.Response('falla', failStatus);
      }
      if (recordIds.length > SyncWorker.maxBatch) {
        statuses.add(413);
        return http.Response('Máximo 200 cambios por envío', 413);
      }
      statuses.add(200);
      return http.Response(
        jsonEncode({
          'success': true,
          'processed_count': recordIds.length,
          'server_timestamp': '2026-11-07T16:00:00Z',
          'processed_record_ids': recordIds,
          'rejected': <Object>[],
        }),
        200,
      );
    });
    return (client: client, requests: requests, statuses: statuses);
  }

  Future<int> outboxSize() async =>
      (await (await db()).query('sync_outbox', where: 'tenant_id = ?', whereArgs: [tenant]))
          .length;

  Future<Set<String>> statuses(List<String> ids) async {
    final rows = await (await db()).query('solidarity_posts', columns: ['id', 'sync_status']);
    final byId = {for (final r in rows) r['id']: r['sync_status'] as String};
    return {for (final id in ids) byId[id]!};
  }

  group('push en lotes de 200', () {
    test('450 pendientes → 3 envíos (200 + 200 + 50), 0 errores 413', () async {
      final ids = await publishMany(450);
      final server = fakeServer();

      final result = await SyncWorker(baseUrl: 'http://api', client: server.client)
          .pushLocalChanges(tenant);

      expect(server.requests.map((r) => r.length), [200, 200, 50]);
      expect(server.statuses, [200, 200, 200]);
      expect(result.success, isTrue);
      expect(result.batchCount, 3);
      expect(result.sentCount, 450);
      expect(result.processedCount, 450);
      expect(await outboxSize(), 0);
      expect(await statuses(ids), {'SYNCED'});
    });

    test('se envían en el mismo orden en que se hicieron (sin repetir)', () async {
      final ids = await publishMany(410);
      final server = fakeServer();
      await SyncWorker(baseUrl: 'http://api', client: server.client).pushLocalChanges(tenant);
      expect(server.requests.expand((r) => r).toList(), ids);
    });

    test('exactamente 200 → un solo envío', () async {
      await publishMany(200);
      final server = fakeServer();
      final result = await SyncWorker(baseUrl: 'http://api', client: server.client)
          .pushLocalChanges(tenant);
      expect(server.requests.length, 1);
      expect(result.batchCount, 1);
      expect(result.success, isTrue);
    });

    test('si falla el 2.º lote (500): el 1.º queda guardado y no se manda el 3.º', () async {
      final ids = await publishMany(450);
      final server = fakeServer(failOnRequest: 2);

      final result = await SyncWorker(baseUrl: 'http://api', client: server.client)
          .pushLocalChanges(tenant);

      expect(server.requests.length, 2);
      expect(result.success, isFalse);
      expect(result.batchCount, 2);
      expect(result.processedCount, 200);
      expect(result.message, contains('500'));
      expect(await outboxSize(), 250);
      expect(await statuses(ids.sublist(0, 200)), {'SYNCED'});
      expect(await statuses(ids.sublist(200)), {'PENDING'});

      // Vuelve la señal: solo se suben los 250 que faltaban.
      final retry = fakeServer();
      final again = await SyncWorker(baseUrl: 'http://api', client: retry.client)
          .pushLocalChanges(tenant);
      expect(retry.requests.map((r) => r.length), [200, 50]);
      expect(retry.requests.expand((r) => r).toList(), ids.sublist(200));
      expect(again.success, isTrue);
      expect(await outboxSize(), 0);
    });

    test('si se corta la señal en el 2.º lote, lo enviado antes no se pierde', () async {
      await publishMany(250);
      final server = fakeServer(failOnRequest: 2, throwInstead: true);

      final result = await SyncWorker(baseUrl: 'http://api', client: server.client)
          .pushLocalChanges(tenant);

      expect(result.success, isFalse);
      expect(result.processedCount, 200);
      expect(result.message, contains('Sin señal'));
      expect(await outboxSize(), 50);
    });

    test('401 en el 1.er lote: se detiene y avisa sesión vencida', () async {
      await publishMany(250);
      final server = fakeServer(failOnRequest: 1, failStatus: 401);

      final result = await SyncWorker(baseUrl: 'http://api', client: server.client)
          .pushLocalChanges(tenant);

      expect(server.requests.length, 1);
      expect(result.unauthorized, isTrue);
      expect(result.processedCount, 0);
      expect(await outboxSize(), 250);
    });

    test('un favor editado en dos lotes queda PENDING hasta subir su último cambio', () async {
      final first = (await publishMany(1)).single;
      await publishMany(199);
      // Segunda edición del mismo favor: cae en el 2.º lote.
      await SyncOutboxDao().queueMutation(
        tenantId: tenant,
        targetTable: 'solidarity_posts',
        recordId: first,
        operation: 'UPSERT',
        payload: {'id': first, 'title': 'Favor editado'},
      );
      final server = fakeServer(failOnRequest: 2);

      await SyncWorker(baseUrl: 'http://api', client: server.client).pushLocalChanges(tenant);

      expect(server.requests.first, contains(first));
      expect(server.requests.last, [first]);
      expect(await statuses([first]), {'PENDING'}); // falta su última edición
    });

    test('nunca envía cambios de otro barrio', () async {
      await publishMany(3, tenantId: otherTenant);
      await publishMany(2);
      final server = fakeServer();
      final result = await SyncWorker(baseUrl: 'http://api', client: server.client)
          .pushLocalChanges(tenant);
      expect(server.requests.single.length, 2);
      expect(result.sentCount, 2);
    });

    test('cola vacía → no llama al servidor', () async {
      final server = fakeServer();
      final result = await SyncWorker(baseUrl: 'http://api', client: server.client)
          .pushLocalChanges(tenant);
      expect(server.requests, isEmpty);
      expect(result.success, isTrue);
      expect(result.batchCount, 0);
    });
  });

  group('cambios pendientes (aviso al cerrar sesión)', () {
    test('cuenta registros, no ediciones repetidas, y solo de su barrio', () async {
      final ids = await publishMany(2);
      await publishMany(4, tenantId: otherTenant);
      await SyncOutboxDao().queueMutation(
        tenantId: tenant,
        targetTable: 'solidarity_posts',
        recordId: ids.first,
        operation: 'UPSERT',
        payload: {'id': ids.first},
      );

      expect(await SyncOutboxDao().countPending(tenant), 2);
      expect(await PendingChanges.count(tenant), 2);
      expect(await PendingChanges.count(otherTenant), 4);
      expect(await PendingChanges.count(null), 0);
    });

    test('texto del aviso en singular, plural o nada', () {
      expect(PendingChanges.logoutWarning(0), isNull);
      expect(
        PendingChanges.logoutWarning(1),
        'Tienes 1 cambio sin sincronizar. Si cierras sesión se perderán.',
      );
      expect(PendingChanges.logoutWarning(5), startsWith('Tienes 5 cambios sin sincronizar'));
    });

    test('después de sincronizar ya no hay aviso', () async {
      await publishMany(3);
      final server = fakeServer();
      await SyncWorker(baseUrl: 'http://api', client: server.client).pushLocalChanges(tenant);
      expect(PendingChanges.logoutWarning(await PendingChanges.count(tenant)), isNull);
    });
  });
}
