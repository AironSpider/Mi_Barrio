import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mi_barrio_app/core/barrio_context/emergency_mode_provider.dart';
import 'package:mi_barrio_app/core/auth/auth_session_store.dart';
import 'package:mi_barrio_app/core/database_sqlite/sqlite_database.dart';
import 'package:mi_barrio_app/core/database_sqlite/sqlite_tables.dart';
import 'package:mi_barrio_app/core/database_sqlite/sync_outbox_dao.dart';
import 'package:mi_barrio_app/core/network/connectivity_monitor.dart';
import 'package:mi_barrio_app/core/sync_manager/sync_coordinator.dart';
import 'package:mi_barrio_app/core/sync_manager/sync_worker.dart';
import 'package:mi_barrio_app/features/profile_me/data/profile_local_storage.dart';
import 'package:mi_barrio_app/features/proximity_services/data/datasources/endorsements_sqlite_ds.dart';
import 'package:mi_barrio_app/features/proximity_services/data/datasources/services_sqlite_ds.dart';
import 'package:mi_barrio_app/features/proximity_services/data/models/endorsement_model.dart';
import 'package:mi_barrio_app/features/proximity_services/data/models/service_model.dart';
import 'package:mi_barrio_app/features/solidarity_network/data/datasources/solidarity_sqlite_ds.dart';
import 'package:mi_barrio_app/features/solidarity_network/data/models/solidarity_post_model.dart';
import 'package:mi_barrio_app/shared/local_distance.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Worker falso que cuenta cuántas veces se sincronizó.
class _CountingWorker extends SyncWorker {
  _CountingWorker() : super(baseUrl: 'http://test');
  int runs = 0;
  Completer<void>? gate;

  @override
  Future<PushResult> pushLocalChanges(String tenantId) async {
    runs++;
    if (gate != null) await gate!.future;
    return const PushResult(success: true);
  }

  @override
  Future<PullResult> pullRemoteChanges(String tenantId) async =>
      const PullResult(success: true);
}

void main() {
  const tenant = 'a1b2c3d4-e5f6-4a8b-9c0d-1e2f3a4b5c6d';
  const otherTenant = 'b2c3d4e5-f6a7-4b8c-9d0e-2f3a4b5c6d7e';
  const me = '5f3a2c1b-1234-4abc-9def-0123456789ab';
  const provider = '9a8b7c6d-5e4f-4a3b-8c2d-1e0f9a8b7c6d';
  const lat = -5.1945; // Piura
  const lng = -80.6328;

  final local = LocalDatabase.instance;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
  });
  setUp(() => local.resetForTesting(path: inMemoryDatabasePath));
  tearDown(() => local.close());

  Future<Database> db() => local.database;

  Future<SolidarityPostModel> publish({
    String title = 'Préstamo de escalera',
  }) => SolidaritySqliteDatasource().publishInThreeClicks(
    tenantId: tenant,
    authorUserId: me,
    modality: SolidarityModality.prestamoHerramienta,
    title: title,
    lat: lat,
    lng: lng,
  );

  group('Esquema v3', () {
    test('crea neighbor_endorsements, users y app_settings', () async {
      final names = (await (await db()).rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table'",
      )).map((r) => r['name']).toSet();
      expect(
        names,
        containsAll(['neighbor_endorsements', 'users', 'app_settings']),
      );
      expect(await (await db()).getVersion(), 3);
    });

    test('un teléfono en v2 sube a v3 sin perder sus oficios', () async {
      final dir = await Directory.systemTemp.createTemp('mi_barrio_v2');
      final path = '${dir.path}${Platform.pathSeparator}v2.db';
      addTearDown(() async {
        await local.close();
        await dir.delete(recursive: true);
      });

      const v2LocalServices = '''
        CREATE TABLE local_services (
          id TEXT PRIMARY KEY, tenant_id TEXT NOT NULL, provider_user_id TEXT NOT NULL,
          category TEXT NOT NULL, title TEXT NOT NULL, description TEXT NOT NULL DEFAULT '',
          is_available_in_emergency INTEGER NOT NULL DEFAULT 0,
          endorsements_count INTEGER NOT NULL DEFAULT 0, lat REAL NOT NULL, lng REAL NOT NULL,
          is_deleted INTEGER NOT NULL DEFAULT 0, updated_at TEXT NOT NULL,
          sync_status TEXT NOT NULL DEFAULT 'SYNCED')''';
      final v2 = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: (d, _) async {
            await d.execute(SqliteTables.createSolidarityPosts);
            await d.execute(v2LocalServices);
            await d.execute(SqliteTables.createSyncOutbox);
            await d.execute(SqliteTables.createSyncState);
          },
        ),
      );
      await v2.insert('local_services', {
        'id': 'c0ffee00-0000-4000-8000-000000000001',
        'tenant_id': tenant,
        'provider_user_id': provider,
        'category': 'GASFITERIA',
        'title': 'Don Pedro',
        'lat': lat,
        'lng': lng,
        'updated_at': '2026-11-07T10:00:00Z',
      });
      await v2.close();

      await local.resetForTesting(path: path);
      final services = await ServicesSqliteDatasource().getServices(tenant);
      expect(services.single.title, 'Don Pedro');
      expect(services.single.ratingAvg, isNull); // columna nueva agregada
      expect(await (await db()).query('users'), isEmpty);
    });
  });

  group('SyncWorker contra el backend (simulado)', () {
    test('push: lo confirmado pasa a SYNCED y sale de la cola', () async {
      final post = await publish();
      late Map<String, dynamic> sentBody;
      final client = MockClient((req) async {
        expect(req.url.path, '/api/v1/sync/push');
        expect(req.headers['X-Tenant-ID'], tenant);
        sentBody = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'success': true,
            'processed_count': 1,
            'server_timestamp': '2026-11-07T15:00:00Z',
            'processed_record_ids': [post.id],
          }),
          200,
        );
      });

      final result = await SyncWorker(
        baseUrl: 'http://api',
        client: client,
      ).pushLocalChanges(tenant);

      expect(result.success, isTrue);
      expect(result.processedCount, 1);
      final payload = (sentBody['mutations'] as List).single['payload'] as Map;
      expect(payload['is_emergency_context'], isFalse);
      expect(await (await db()).query('sync_outbox'), isEmpty);
      final row = (await (await db()).query('solidarity_posts')).single;
      expect(row['sync_status'], 'SYNCED');
    });

    test('push: si el servidor falla (500), la cola queda intacta', () async {
      await publish();
      final client = MockClient((_) async => http.Response('error', 500));
      final result = await SyncWorker(
        baseUrl: 'http://api',
        client: client,
      ).pushLocalChanges(tenant);
      expect(result.success, isFalse);
      expect((await (await db()).query('sync_outbox')).length, 1);
      expect(
        (await (await db()).query('solidarity_posts')).single['sync_status'],
        'PENDING',
      );
    });

    test(
      'push: un rechazo terminal pasa a FAILED y sale de la cola',
      () async {
        final post = await publish();
        final client = MockClient(
          (_) async => http.Response(
            jsonEncode({
              'success': true,
              'processed_count': 0,
              'server_timestamp': '2026-11-07T15:00:00Z',
              'processed_record_ids': <String>[],
              'rejected': [
                {
                  'record_id': post.id,
                  'target_table': 'solidarity_posts',
                  'reason': 'autor no registrado',
                },
              ],
            }),
            200,
          ),
        );

        final result = await SyncWorker(
          baseUrl: 'http://api',
          client: client,
        ).pushLocalChanges(tenant);

        expect(result.success, isFalse);
        expect(result.message, contains('autor no registrado'));
        expect(await (await db()).query('sync_outbox'), isEmpty);
        expect(
          (await (await db()).query('solidarity_posts')).single['sync_status'],
          'FAILED',
        );
      },
    );

    test('push: un 401 invalida la sesión y notifica al provider', () async {
      await publish();
      await AuthSessionStore.instance.save({'token': 'expired-token'});
      final sessionExpired = AuthSessionStore.instance.onSessionExpired.first;
      final client = MockClient((_) async => http.Response('unauthorized', 401));

      final result = await SyncWorker(
        baseUrl: 'http://api',
        client: client,
      ).pushLocalChanges(tenant);

      await sessionExpired;
      expect(result.unauthorized, isTrue);
      expect(AuthSessionStore.instance.token, isNull);
    });

    test('pull: un 401 invalida la sesión', () async {
      await AuthSessionStore.instance.save({'token': 'expired-token'});
      final sessionExpired = AuthSessionStore.instance.onSessionExpired.first;
      final client = MockClient((_) async => http.Response('unauthorized', 401));

      final result = await SyncWorker(
        baseUrl: 'http://api',
        client: client,
      ).pullRemoteChanges(tenant);

      await sessionExpired;
      expect(result.unauthorized, isTrue);
      expect(AuthSessionStore.instance.token, isNull);
    });

    test('cambiar de usuario borra solo sus filas y outbox', () async {
      await publish();
      final otherPost = await SolidaritySqliteDatasource().publishInThreeClicks(
        tenantId: tenant,
        authorUserId: provider,
        modality: SolidarityModality.prestamoHerramienta,
        title: 'Post de otra cuenta',
        lat: lat,
        lng: lng,
      );

      await SyncOutboxDao().clearUserData(tenantId: tenant, userId: me);

      final rows = await (await db()).query('solidarity_posts');
      expect(rows.map((row) => row['id']), [otherPost.id]);
      expect(await (await db()).query('sync_outbox'), isEmpty);
    });

    test('push: el perfil se sincroniza sin permitir asignar un rol', () async {
      final profile = await ProfileLocalStorage().saveProfile(
        userId: me,
        tenantId: tenant,
        fullName: 'Ana Torres',
        homeLat: lat,
        homeLng: lng,
      );
      late Map<String, dynamic> sentBody;
      final client = MockClient((request) async {
        sentBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'success': true,
            'processed_count': 1,
            'server_timestamp': '2026-11-07T15:00:00Z',
            'processed_record_ids': [profile.id],
          }),
          200,
        );
      });

      final result = await SyncWorker(
        baseUrl: 'http://api',
        client: client,
      ).pushLocalChanges(tenant);

      expect(result.success, isTrue);
      expect(result.processedCount, 1);
      final mutation = (sentBody['mutations'] as List).single as Map;
      expect(mutation['target_table'], 'users');
      expect((mutation['payload'] as Map).containsKey('role'), isFalse);
      expect(await (await db()).query('sync_outbox'), isEmpty);
      expect(
        (await (await db()).query('users')).single['sync_status'],
        'SYNCED',
      );
    });

    test('pull: guarda posts y servicios, sin pisar PENDING ni aceptar otro barrio', () async {
      final mine = await publish(title: 'Versión local sin subir');
      final client = MockClient((req) async {
        expect(req.url.path, '/api/v1/sync/pull');
        return http.Response(
          jsonEncode({
            'server_timestamp': '2026-11-07T15:00:00.123456Z',
            'has_more': false,
            'delta': {
              'solidarity_posts': [
                {
                  'id': mine.id, // el servidor tiene una versión vieja
                  'tenant_id': tenant,
                  'author_user_id': me,
                  'flow_type': 'SOLICITO_AYUDA',
                  'modality': 'PRESTAMO_HERRAMIENTA',
                  'title': 'Versión vieja del servidor',
                  'description': null,
                  'is_emergency_context': false,
                  'status': 'DISPONIBLE',
                  'lat': lat,
                  'lng': lng,
                  'is_deleted': false,
                  'updated_at': '2026-11-07T09:00:00+00:00',
                  'created_at': '2026-11-07T09:00:00+00:00',
                },
                {
                  'id': 'deadbeef-0000-4000-8000-000000000002',
                  'tenant_id': otherTenant, // nunca debe guardarse
                  'author_user_id': me,
                  'flow_type': 'SOLICITO_AYUDA',
                  'modality': 'PRESTAMO_HERRAMIENTA',
                  'title': 'De otro barrio',
                  'lat': lat,
                  'lng': lng,
                  'is_deleted': false,
                  'updated_at': '2026-11-07T09:00:00+00:00',
                },
              ],
              'local_services': [
                {
                  'id': 'c0ffee00-0000-4000-8000-000000000003',
                  'tenant_id': tenant,
                  'provider_user_id': provider,
                  'category': 'ELECTRICIDAD',
                  'title': 'Rosa, electricista',
                  'description': 'Cortocircuitos',
                  'is_available_in_emergency': true,
                  'endorsements_count': 9,
                  'rating_avg': 4.6,
                  'lat': lat,
                  'lng': lng,
                  'is_deleted': false,
                  'updated_at': '2026-11-07T08:00:00+00:00',
                  'created_at': '2026-11-07T08:00:00+00:00',
                },
              ],
            },
          }),
          200,
        );
      });

      final result = await SyncWorker(
        baseUrl: 'http://api',
        client: client,
      ).pullRemoteChanges(tenant);

      expect(result.success, isTrue);
      expect(result.skippedPendingCount, 1);
      final posts = await SolidaritySqliteDatasource().getActivePosts(tenant);
      expect(posts.single.title, 'Versión local sin subir'); // no se pisó
      expect(posts.single.isPending, isTrue);

      final services = await ServicesSqliteDatasource().getServices(tenant);
      expect(services.single.title, 'Rosa, electricista');
      expect(services.single.isAvailableInEmergency, isTrue);
      expect(services.single.ratingAvg, 4.6);
      expect(services.single.isPending, isFalse);

      final state = (await (await db()).query('sync_state')).single;
      expect(state['last_pulled_at'], '2026-11-07T15:00:00.123456Z');
    });

    test('sin red: push y pull fallan sin lanzar excepciones', () async {
      await publish();
      final client = MockClient(
        (_) async => throw const SocketException('sin red'),
      );
      final worker = SyncWorker(baseUrl: 'http://api', client: client);
      expect((await worker.pushLocalChanges(tenant)).success, isFalse);
      expect((await worker.pullRemoteChanges(tenant)).success, isFalse);
      expect((await (await db()).query('sync_outbox')).length, 1);
    });
  });

  group('SyncCoordinator (Checkpoint 1)', () {
    late StreamController<ConnectionStatus> connection;
    late _CountingWorker worker;
    var online = false;

    setUp(() async {
      connection = StreamController<ConnectionStatus>.broadcast();
      worker = _CountingWorker();
      online = false;
      await SyncCoordinator.instance.start(
        worker: worker,
        connectionChanges: connection.stream,
        isOnline: () => online,
        tenantId: () => tenant,
        interval: const Duration(hours: 1),
        syncImmediately: false,
      );
    });
    tearDown(() async {
      await SyncCoordinator.instance.stop();
      await connection.close();
    });

    test('sin red no intenta subir; al volver internet sincroniza', () async {
      await SyncCoordinator.instance.syncNow();
      expect(worker.runs, 0);
      expect(SyncCoordinator.instance.phase.value, SyncPhase.offline);

      online = true;
      connection.add(ConnectionStatus.online);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(worker.runs, 1);
      expect(SyncCoordinator.instance.lastSuccess.value, isNotNull);
    });

    test('publicar con red dispara la sincronización sola', () async {
      online = true;
      await publish();
      await Future<void>.delayed(const Duration(milliseconds: 700));
      expect(worker.runs, 1);
    });

    test('nunca corre dos sincronizaciones a la vez', () async {
      online = true;
      worker.gate = Completer<void>();
      final first = SyncCoordinator.instance.syncNow();
      await SyncCoordinator.instance.syncNow(); // llega durante la primera
      await SyncCoordinator.instance.syncNow();
      expect(worker.runs, 1);
      worker.gate!.complete();
      await first;
      expect(worker.runs, 2); // una sola ronda extra, no dos
    });
  });

  group('Calificación con estrellas', () {
    late LocalServiceModel service;
    setUp(() async {
      service = await ServicesSqliteDatasource().insertService(
        tenantId: tenant,
        providerUserId: provider,
        category: ServiceCategory.gasfiteria,
        title: 'Don Pedro, gasfitero',
        lat: lat,
        lng: lng,
      );
    });

    test('el id es el mismo en cualquier teléfono (UUID v5)', () {
      expect(
        EndorsementModel.idFor(service.id, me),
        EndorsementModel.idFor(service.id, me),
      );
      expect(
        EndorsementModel.idFor(service.id, me),
        isNot(EndorsementModel.idFor(service.id, provider)),
      );
    });

    test('calificar dos veces edita la misma fila (upsert)', () async {
      final ds = EndorsementsSqliteDatasource();
      await ds.rateService(
        tenantId: tenant,
        serviceId: service.id,
        endorserUserId: me,
        rating: 3,
      );
      await ds.rateService(
        tenantId: tenant,
        serviceId: service.id,
        endorserUserId: me,
        rating: 5,
        shortComment: '  Muy puntual  ',
      );

      final list = await ds.listForService(tenant, service.id);
      expect(list.single.rating, 5);
      expect(list.single.shortComment, 'Muy puntual');
      expect(list.single.isPending, isTrue);
      expect((await ds.myRating(service.id, me))!.rating, 5);
    });

    test('Dar visto bueno guarda en SQLite y encola la mutación', () async {
      final ds = EndorsementsSqliteDatasource();
      final endorsement = await ds.rateService(
        tenantId: tenant,
        serviceId: service.id,
        endorserUserId: me,
      );

      expect(endorsement.rating, isNull);
      expect(endorsement.isPending, isTrue);
      expect((await ds.myRating(service.id, me))!.id, endorsement.id);
      final pending = await (await db()).query(
        'sync_outbox',
        where: 'target_table = ? AND record_id = ?',
        whereArgs: [EndorsementModel.table, endorsement.id],
      );
      expect(pending, hasLength(1));
      final payload =
          jsonDecode(pending.single['payload_json'] as String) as Map;
      expect(payload['service_id'], service.id);
      expect(payload['endorser_user_id'], me);
      expect(payload['rating'], isNull);
      expect(payload['is_deleted'], isFalse);
    });

    test('retirar visto bueno guarda borrado lógico en la cola', () async {
      final ds = EndorsementsSqliteDatasource();
      final created = await ds.rateService(
        tenantId: tenant,
        serviceId: service.id,
        endorserUserId: me,
      );

      final removed = await ds.removeEndorsement(
        tenantId: tenant,
        serviceId: service.id,
        endorserUserId: me,
      );

      expect(removed.id, created.id);
      expect(removed.isDeleted, isTrue);
      expect(removed.isPending, isTrue);
      expect(await ds.myRating(service.id, me), isNull);
      final pending = await (await db()).query(
        'sync_outbox',
        where: 'target_table = ? AND record_id = ?',
        whereArgs: [EndorsementModel.table, created.id],
        orderBy: 'outbox_id DESC',
        limit: 1,
      );
      final payload =
          jsonDecode(pending.single['payload_json'] as String) as Map;
      expect(payload['is_deleted'], isTrue);
    });

    test('permite estrellas vacías y rechaza datos inválidos', () async {
      final ds = EndorsementsSqliteDatasource();
      final empty = await ds.rateService(
        tenantId: tenant,
        serviceId: service.id,
        endorserUserId: me,
      );
      expect(empty.rating, isNull);

      Future<void> rate({
        int? rating,
        String? comment,
        String user = me,
        String? sid,
      }) => ds.rateService(
        tenantId: tenant,
        serviceId: sid ?? service.id,
        endorserUserId: user,
        rating: rating,
        shortComment: comment,
      );

      await expectLater(rate(rating: 0), throwsArgumentError);
      await expectLater(rate(rating: 6), throwsArgumentError);
      await expectLater(
        rate(rating: 4, comment: 'x' * 141),
        throwsArgumentError,
      );
      await expectLater(
        rate(rating: 5, user: provider),
        throwsArgumentError,
      ); // su propio servicio
      await expectLater(
        rate(rating: 5, sid: 'c0ffee00-0000-4000-8000-0000000000ff'),
        throwsArgumentError,
      );
    });
  });

  group('Perfil (users)', () {
    test('guarda PENDING, conserva el rol y no lo envía al servidor', () async {
      final storage = ProfileLocalStorage();
      await (await db()).insert('users', {
        'id': me,
        'tenant_id': tenant,
        'full_name': 'Ana',
        'home_lat': lat,
        'home_lng': lng,
        'role': 'LIDER_VECINAL',
        'updated_at': '2026-11-07T08:00:00Z',
      });

      final saved = await storage.saveProfile(
        userId: me,
        tenantId: tenant,
        fullName: ' Ana Torres ',
        homeLat: lat,
        homeLng: lng,
        email: 'ana@correo.pe',
        whatsapp: '+51 987 654 321',
        publisherType: 'BODEGA',
        publisherName: 'Bodega Anita',
      );
      expect(saved.fullName, 'Ana Torres');
      expect(saved.role, 'LIDER_VECINAL');
      expect(saved.initials, 'AT');
      expect((await storage.getProfile(me))!.isPending, isTrue);

      final outbox = (await (await db()).query('sync_outbox')).single;
      final payload = jsonDecode(outbox['payload_json'] as String) as Map;
      expect(payload.containsKey('role'), isFalse);
      expect(payload['tutorial_completed'], isFalse);
    });

    test('rechaza correo, WhatsApp, redes o tipo inválidos', () async {
      final storage = ProfileLocalStorage();
      Future<void> save({
        String email = 'a@b.pe',
        String whatsapp = '987654321',
        String fb = 'https://facebook.com/ana',
        String type = 'EMPRENDEDOR',
        String name = 'Ana',
      }) => storage.saveProfile(
        userId: me,
        tenantId: tenant,
        fullName: name,
        homeLat: lat,
        homeLng: lng,
        email: email,
        whatsapp: whatsapp,
        facebookUrl: fb,
        publisherType: type,
      );

      await expectLater(save(email: 'no-es-correo'), throwsArgumentError);
      await expectLater(save(whatsapp: 'abc'), throwsArgumentError);
      await expectLater(save(fb: 'javascript:alert(1)'), throwsArgumentError);
      await expectLater(save(type: 'HACKER'), throwsArgumentError);
      await expectLater(save(name: '   '), throwsArgumentError);
      expect(await storage.getProfile(me), isNull);
    });
  });

  group('Distancia local (haversine)', () {
    test('mismo punto = 0 km', () {
      expect(LocalDistance.km(lat, lng, lat, lng), 0);
    });
    test('1 grado de longitud en el ecuador ≈ 111.19 km', () {
      expect(LocalDistance.km(0, 0, 0, 1), closeTo(111.19, 0.01));
    });
    test('Piura → Lima ≈ 860 km', () {
      expect(LocalDistance.km(lat, lng, -12.0464, -77.0428), closeTo(860, 25));
    });
    test('etiqueta legible', () {
      expect(LocalDistance.label(0.35), '350 m');
      expect(LocalDistance.label(2.44), '2,4 km');
    });
  });

  group('Modo emergencia', () {
    setUp(() => EmergencyModeProvider.instance.resetForTesting());

    test('el toggle local se guarda y se recupera al reabrir', () async {
      final p = EmergencyModeProvider.instance;
      await p.setLocal(true);
      expect(p.isActive.value, isTrue);

      p.resetForTesting();
      await p.load();
      expect(p.isActive.value, isTrue);
    });

    test(
      'si la junta vecinal la activa, el vecino no puede apagarla',
      () async {
        final p = EmergencyModeProvider.instance;
        await p.load();
        p.setTenantFlag(true);
        expect(p.isActive.value, isTrue);
        expect(p.isLockedByTenant.value, isTrue);
        await p.setLocal(false);
        expect(p.isActive.value, isTrue);
        p.setTenantFlag(false);
        expect(p.isActive.value, isFalse);
      },
    );
  });
}
