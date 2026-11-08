import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mi_barrio_app/core/database_sqlite/sqlite_database.dart';
import 'package:mi_barrio_app/core/database_sqlite/sqlite_tables.dart';
import 'package:mi_barrio_app/core/database_sqlite/sync_outbox_dao.dart';
import 'package:mi_barrio_app/core/network/connectivity_monitor.dart';
import 'package:mi_barrio_app/core/sync_manager/sync_coordinator.dart';
import 'package:mi_barrio_app/core/sync_manager/sync_worker.dart';
import 'package:mi_barrio_app/features/solidarity_network/data/datasources/solidarity_sqlite_ds.dart';
import 'package:mi_barrio_app/features/solidarity_network/data/models/solidarity_post_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Worker falso: cada ronda devuelve el siguiente resultado del guion.
class _ScriptedWorker extends SyncWorker {
  _ScriptedWorker(this.script) : super(baseUrl: 'http://test');
  final List<(PushResult, PullResult)> script;
  final times = <DateTime>[];
  int get runs => times.length;

  (PushResult, PullResult) get _current => script[(runs - 1).clamp(0, script.length - 1)];

  @override
  Future<PushResult> pushLocalChanges(String tenantId) async {
    times.add(DateTime.now());
    return _current.$1;
  }

  @override
  Future<PullResult> pullRemoteChanges(String tenantId) async => _current.$2;
}

const _ok = (PushResult(success: true), PullResult(success: true));
const _serverDown = (
  PushResult(success: false, message: 'El servidor respondio 503', retryable: true),
  PullResult(success: false, message: 'El servidor respondio 503', retryable: true),
);

/// Esperas cortas para que el test sea rápido (misma lógica que 2-4-8-16 s).
const _fast = [
  Duration(milliseconds: 40),
  Duration(milliseconds: 80),
  Duration(milliseconds: 160),
  Duration(milliseconds: 320),
];

void main() {
  const tenant = 'a1b2c3d4-e5f6-4a8b-9c0d-1e2f3a4b5c6d';
  const me = '5f3a2c1b-1234-4abc-9def-0123456789ab';
  const lat = -5.1945;
  const lng = -80.6328;
  final local = LocalDatabase.instance;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
  });
  setUp(() => local.resetForTesting(path: inMemoryDatabasePath));
  tearDown(() async {
    await SyncCoordinator.instance.stop();
    await local.close();
  });

  Future<Database> db() => local.database;

  Future<SolidarityPostModel> publish(String title) => SolidaritySqliteDatasource().publishInThreeClicks(
        tenantId: tenant, authorUserId: me, modality: SolidarityModality.prestamoHerramienta,
        title: title, lat: lat, lng: lng);

  // ─────────────────────────── Reintentos ───────────────────────────
  group('Reintentos con espera creciente (2, 4, 8, 16 s)', () {
    late StreamController<ConnectionStatus> connection;
    var online = true;

    setUp(() {
      connection = StreamController<ConnectionStatus>.broadcast();
      online = true;
    });
    tearDown(() => connection.close());

    Future<void> startWith(SyncWorker worker) => SyncCoordinator.instance.start(
          worker: worker,
          connectionChanges: connection.stream,
          isOnline: () => online,
          tenantId: () => tenant,
          interval: const Duration(hours: 1), // que no interfiera el respaldo periódico
          retryDelays: _fast,
        );

    test('las esperas reales son 2, 4, 8 y 16 segundos', () {
      expect(SyncCoordinator.defaultRetryDelays.map((d) => d.inSeconds), [2, 4, 8, 16]);
    });

    test('servidor caído: 1 intento + 4 reintentos, cada vez esperando más, y para', () async {
      final waits = <Duration?>[];
      void listener() => waits.add(SyncCoordinator.instance.nextRetry.value);
      SyncCoordinator.instance.nextRetry.addListener(listener);
      addTearDown(() => SyncCoordinator.instance.nextRetry.removeListener(listener));

      final worker = _ScriptedWorker([_serverDown]);
      await startWith(worker);
      await Future<void>.delayed(const Duration(milliseconds: 1200));

      expect(worker.runs, 5, reason: '1 intento + 4 reintentos, ni uno más');
      expect(waits.whereType<Duration>().toList(), _fast);
      final gaps = [for (var i = 1; i < worker.times.length; i++) worker.times[i].difference(worker.times[i - 1])];
      for (var i = 0; i < gaps.length; i++) {
        expect(gaps[i], greaterThanOrEqualTo(_fast[i] - const Duration(milliseconds: 5)),
            reason: 'reintento ${i + 1} esperó lo debido');
      }
      expect(SyncCoordinator.instance.phase.value, SyncPhase.error);
      expect(SyncCoordinator.instance.nextRetry.value, isNull);
    });

    test('se recupera al 3.er intento: deja de reintentar y reinicia la cuenta', () async {
      final worker = _ScriptedWorker([_serverDown, _serverDown, _ok]);
      await startWith(worker);
      await Future<void>.delayed(const Duration(milliseconds: 700));

      expect(worker.runs, 3);
      expect(SyncCoordinator.instance.phase.value, SyncPhase.idle);
      expect(SyncCoordinator.instance.lastSuccess.value, isNotNull);
      expect(SyncCoordinator.instance.retryAttempt, 0);
      expect(SyncCoordinator.instance.nextRetry.value, isNull);
    });

    test('sesión vencida (401): NO se reintenta', () async {
      final worker = _ScriptedWorker([
        (const PushResult(success: false, unauthorized: true), const PullResult(success: true)),
      ]);
      await startWith(worker);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(worker.runs, 1);
      expect(SyncCoordinator.instance.nextRetry.value, isNull);
    });

    test('dato rechazado (falla definitiva): NO se reintenta', () async {
      final worker = _ScriptedWorker([
        (const PushResult(success: false, message: 'El servidor rechazó 1 cambio(s)'), const PullResult(success: true)),
      ]);
      await startWith(worker);
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(worker.runs, 1);
    });

    test('se pierde la red: se cancela el reintento; al volver, sincroniza y la cuenta empieza de nuevo', () async {
      final worker = _ScriptedWorker([_serverDown, _ok]);
      await startWith(worker);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(SyncCoordinator.instance.nextRetry.value, _fast.first);

      online = false;
      connection.add(ConnectionStatus.offline);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(worker.runs, 1, reason: 'sin red no se gasta el reintento');
      expect(SyncCoordinator.instance.retryAttempt, 0);

      online = true;
      connection.add(ConnectionStatus.online);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(worker.runs, 2);
      expect(SyncCoordinator.instance.phase.value, SyncPhase.idle);
    });

    test('stop() (cerrar sesión) cancela los reintentos pendientes', () async {
      final worker = _ScriptedWorker([_serverDown]);
      await startWith(worker);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await SyncCoordinator.instance.stop();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(worker.runs, 1);
      expect(SyncCoordinator.instance.nextRetry.value, isNull);
    });
  });

  // ───────────────────── Qué falla es temporal ─────────────────────
  group('Clasificación: temporal (reintentar) vs definitiva', () {
    test('5xx, 408 y 429 son temporales; 400, 403, 404 y 413 no', () {
      for (final s in [500, 502, 503, 504, 408, 429]) {
        expect(isTransientHttpStatus(s), isTrue, reason: '$s');
      }
      for (final s in [400, 401, 403, 404, 413, 422]) {
        expect(isTransientHttpStatus(s), isFalse, reason: '$s');
      }
    });

    test('push y pull marcan retryable según la respuesta', () async {
      await publish('Escalera');
      for (final (status, retryable) in [(503, true), (429, true), (403, false)]) {
        final client = MockClient((_) async => http.Response('x', status));
        final worker = SyncWorker(baseUrl: 'http://api', client: client);
        expect((await worker.pushLocalChanges(tenant)).retryable, retryable, reason: 'push $status');
        expect((await worker.pullRemoteChanges(tenant)).retryable, retryable, reason: 'pull $status');
      }
      final noAnswer = SyncWorker(
          baseUrl: 'http://api', client: MockClient((_) async => throw const SocketException('timeout')));
      expect((await noAnswer.pushLocalChanges(tenant)).retryable, isTrue);
      expect((await noAnswer.pullRemoteChanges(tenant)).retryable, isTrue);
    });
  });

  // ──────────────── Pull: no perder la versión del servidor ────────────────
  group('Pull con cambios sin subir', () {
    Map<String, Object?> serverPost(String id, String title, String serverUpdatedAt,
            {String status = 'DISPONIBLE'}) =>
        {
          'id': id, 'tenant_id': tenant, 'author_user_id': me, 'flow_type': 'SOLICITO_AYUDA',
          'modality': 'PRESTAMO_HERRAMIENTA', 'title': title, 'description': null,
          'is_emergency_context': false, 'status': status, 'lat': lat, 'lng': lng, 'is_deleted': false,
          'updated_at': '2026-11-07T13:00:00+00:00', 'server_updated_at': serverUpdatedAt,
        };

    test('push falla (5xx), pull salta mi fila; si el servidor gana (LWW) igual llega su versión', () async {
      final mine = await publish('Mi versión vieja');
      final sinceSeen = <String?>[];
      var pulls = 0;
      final client = MockClient((req) async {
        if (req.url.path == '/api/v1/sync/push') {
          // El servidor acepta el envío pero se queda con SU versión (más nueva).
          return http.Response(jsonEncode({'processed_record_ids': [mine.id], 'rejected': []}), 200);
        }
        pulls++;
        sinceSeen.add(req.url.queryParameters['since']);
        return http.Response(
          jsonEncode({
            'server_timestamp': '2026-11-07T15:0$pulls:00Z',
            'delta': {
              'solidarity_posts': [serverPost(mine.id, 'Versión del servidor', '2026-11-07T14:00:00+00:00')],
            },
          }),
          200,
        );
      });
      final worker = SyncWorker(baseUrl: 'http://api', client: client);

      // 1) Pull mientras mi cambio sigue en la cola: no se pisa…
      expect((await worker.pullRemoteChanges(tenant)).skippedPendingCount, 1);
      expect((await SolidaritySqliteDatasource().getPost(tenant, mine.id))!.title, 'Mi versión vieja');
      // …y el cursor NO pasa por encima de esa fila.
      expect((await (await db()).query('sync_state')).single['last_pulled_at'], '2026-11-07T14:00:00.000Z');

      // 2) Se sube (el servidor se quedó con la suya) y el siguiente pull la trae.
      await worker.pushLocalChanges(tenant);
      await worker.pullRemoteChanges(tenant);
      expect(sinceSeen.last, '2026-11-07T14:00:00.000Z');
      final post = (await SolidaritySqliteDatasource().getPost(tenant, mine.id))!;
      expect(post.title, 'Versión del servidor');
      expect(post.syncStatus, SqliteTables.syncSynced);
      expect((await (await db()).query('sync_state')).single['last_pulled_at'], '2026-11-07T15:02:00Z');
    });

    test('un registro FAILED (ya fuera de la cola) recibe la verdad del servidor', () async {
      final post = await publish('Coordinado por mí');
      // El servidor lo rechazó: salió de la cola como FAILED.
      await (await db()).delete('sync_outbox');
      await (await db()).update('solidarity_posts', {'sync_status': SqliteTables.syncFailed},
          where: 'id = ?', whereArgs: [post.id]);

      final client = MockClient((_) async => http.Response(
            jsonEncode({
              'server_timestamp': '2026-11-07T15:00:00Z',
              'delta': {
                'solidarity_posts': [
                  serverPost(post.id, 'Coordinado por mí', '2026-11-07T14:30:00+00:00', status: 'COMPLETADO'),
                ],
              },
            }),
            200,
          ));
      await SyncWorker(baseUrl: 'http://api', client: client).pullRemoteChanges(tenant);

      final now = (await SolidaritySqliteDatasource().getPost(tenant, post.id))!;
      expect(now.status, SolidarityStatus.completado, reason: 'antes quedaba congelado para siempre');
      expect(now.syncStatus, SqliteTables.syncSynced);
    });
  });

  // ─────────────────────── Cierre forzado ───────────────────────
  group('Cerrar la app a la fuerza durante un sync NO pierde nada', () {
    late Directory dir;
    late String path;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('mi_barrio_crash');
      path = '${dir.path}${Platform.pathSeparator}app.db';
      await local.resetForTesting(path: path);
    });
    tearDown(() async {
      await local.close();
      await dir.delete(recursive: true);
    });

    Future<void> killAndReopen() async {
      await local.close(); // el proceso muere: se cierra la base
      await local.resetForTesting(path: path); // la app vuelve a abrir
    }

    test('el servidor recibió el envío pero la app murió antes de la respuesta → se reenvía igual, sin duplicar', () async {
      final posts = [for (var i = 0; i < 3; i++) await publish('Favor $i')];
      String? firstBody;
      final dies = MockClient((req) async {
        firstBody = req.body; // el servidor lo recibió…
        throw const SocketException('la app se cerró antes de la respuesta');
      });
      final cut = await SyncWorker(baseUrl: 'http://api', client: dies).pushLocalChanges(tenant);
      expect(cut.success, isFalse);
      expect(cut.retryable, isTrue);

      await killAndReopen();
      expect(await (await db()).query('sync_outbox'), hasLength(3), reason: 'la cola sobrevive al cierre');

      String? secondBody;
      final ok = MockClient((req) async {
        secondBody = req.body;
        final ids = [for (final m in (jsonDecode(req.body)['mutations'] as List)) (m as Map)['record_id']];
        return http.Response(jsonEncode({'processed_record_ids': ids, 'rejected': []}), 200);
      });
      expect((await SyncWorker(baseUrl: 'http://api', client: ok).pushLocalChanges(tenant)).success, isTrue);

      // Mismos ids y mismos datos: el servidor hace "upsert", no crea copias.
      List<Object?> mutations(String? body) =>
          [for (final m in (jsonDecode(body!)['mutations'] as List)) {...(m as Map)}..remove('client_sync_timestamp')];
      expect(mutations(secondBody), mutations(firstBody));
      expect(await (await db()).query('sync_outbox'), isEmpty);
      for (final p in posts) {
        expect((await SolidaritySqliteDatasource().getPost(tenant, p.id))!.syncStatus, SqliteTables.syncSynced);
      }
    });

    test('muere entre dos lotes: al reabrir solo se envía lo que faltaba', () async {
      final posts = [for (var i = 0; i < 250; i++) await publish('Favor $i')];
      var calls = 0;
      final dies = MockClient((req) async {
        calls++;
        if (calls == 2) throw const SocketException('la app se cerró');
        final ids = [for (final m in (jsonDecode(req.body)['mutations'] as List)) (m as Map)['record_id']];
        return http.Response(jsonEncode({'processed_record_ids': ids, 'rejected': []}), 200);
      });
      await SyncWorker(baseUrl: 'http://api', client: dies).pushLocalChanges(tenant);

      await killAndReopen();
      final resent = <Object?>[];
      final ok = MockClient((req) async {
        final ids = [for (final m in (jsonDecode(req.body)['mutations'] as List)) (m as Map)['record_id']];
        resent.addAll(ids);
        return http.Response(jsonEncode({'processed_record_ids': ids, 'rejected': []}), 200);
      });
      await SyncWorker(baseUrl: 'http://api', client: ok).pushLocalChanges(tenant);

      expect(resent, [for (final p in posts.sublist(200)) p.id]);
      expect(await (await db()).query('sync_outbox'), isEmpty);
    });

    test('se corta en medio del pull: no queda nada a medias y el siguiente pull trae todo', () async {
      Map<String, Object?> row(String id, Object? title) => {
            'id': id, 'tenant_id': tenant, 'author_user_id': 'otro', 'flow_type': 'SOLICITO_AYUDA',
            'modality': 'PRESTAMO_HERRAMIENTA', 'title': title, 'lat': lat, 'lng': lng,
            'is_deleted': false, 'updated_at': '2026-11-07T10:00:00Z',
            'server_updated_at': '2026-11-07T10:00:00Z',
          };
      // La 3.ª fila revienta a mitad de la escritura (igual que un cierre).
      final broken = MockClient((_) async => http.Response(
          jsonEncode({'server_timestamp': '2026-11-07T15:00:00Z', 'delta': {
            'solidarity_posts': [row('p1', 'Uno'), row('p2', 'Dos'), row('p3', null)],
          }}), 200));
      final failed = await SyncWorker(baseUrl: 'http://api', client: broken).pullRemoteChanges(tenant);
      expect(failed.success, isFalse);

      await killAndReopen();
      expect(await (await db()).query('solidarity_posts'), isEmpty, reason: 'ni p1 ni p2 a medias');
      expect(await (await db()).query('sync_state'), isEmpty, reason: 'el cursor no avanzó');

      final good = MockClient((_) async => http.Response(
          jsonEncode({'server_timestamp': '2026-11-07T15:01:00Z', 'delta': {
            'solidarity_posts': [row('p1', 'Uno'), row('p2', 'Dos'), row('p3', 'Tres')],
          }}), 200));
      expect((await SyncWorker(baseUrl: 'http://api', client: good).pullRemoteChanges(tenant)).success, isTrue);
      expect(await (await db()).query('solidarity_posts'), hasLength(3));
    });

    test('se corta mientras se guarda una publicación: ni el favor ni la cola quedan a medias', () async {
      final broken = _ExplodingOutbox();
      await expectLater(
        SolidaritySqliteDatasource(outboxDao: broken).publishInThreeClicks(
            tenantId: tenant, authorUserId: me, modality: SolidarityModality.prestamoHerramienta,
            title: 'A medias', lat: lat, lng: lng),
        throwsA(isA<StateError>()),
      );
      await killAndReopen();
      expect(await (await db()).query('solidarity_posts'), isEmpty);
      expect(await (await db()).query('sync_outbox'), isEmpty);
    });

    test('transacción SQLite sin confirmar al morir la app → al reabrir no existe', () async {
      await db(); // la app ya creó sus tablas
      await local.close();
      final raw = await databaseFactoryFfi.openDatabase(path);
      try {
        await raw.execute('BEGIN');
        await raw.insert('sync_outbox', {
          'tenant_id': tenant, 'target_table': 'solidarity_posts', 'record_id': 'x',
          'operation': 'UPSERT', 'payload_json': '{}', 'created_at': '2026-11-07T10:00:00Z',
        });
        expect(await raw.query('sync_outbox'), hasLength(1)); // dentro de la transacción existe
      } finally {
        await raw.close(); // muere sin COMMIT
      }
      await local.resetForTesting(path: path);
      expect(await (await db()).query('sync_outbox'), isEmpty);
    });
  });
}

/// Simula que la app muere justo al encolar (dentro de la transacción).
class _ExplodingOutbox extends SyncOutboxDao {
  @override
  Future<void> queueMutation({
    required String tenantId,
    required String targetTable,
    required String recordId,
    required String operation,
    required Map<String, dynamic> payload,
    DatabaseExecutor? executor,
  }) async {
    throw StateError('la app se cerró al guardar');
  }
}
