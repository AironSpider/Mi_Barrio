import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mi_barrio_app/core/database_sqlite/sqlite_database.dart';
import 'package:mi_barrio_app/core/database_sqlite/sqlite_tables.dart';
import 'package:mi_barrio_app/core/database_sqlite/sync_outbox_dao.dart';
import 'package:mi_barrio_app/core/network/api_client.dart';
import 'package:mi_barrio_app/core/sync_manager/sync_worker.dart';
import 'package:mi_barrio_app/features/auth_barrio/data/datasources/auth_remote_datasource.dart';
import 'package:mi_barrio_app/features/auth_barrio/data/repositories/auth_repository_impl.dart';
import 'package:mi_barrio_app/features/emergency_support/data/datasources/support_groups_sqlite_ds.dart';
import 'package:mi_barrio_app/features/emergency_support/data/models/support_group_model.dart';
import 'package:mi_barrio_app/features/profile_me/data/profile_local_storage.dart';
import 'package:mi_barrio_app/features/profile_me/data/profile_sync.dart';
import 'package:mi_barrio_app/features/profile_me/data/tutorial_progress.dart';
import 'package:mi_barrio_app/features/proximity_services/presentation/widgets/offer_service_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Sprint 11 · Dev 2: grupos de apoyo sin red (SQLite v5), bandera del tutorial
/// y perfil propio sincronizado (rol real, nombre, tutorial).
void main() {
  const tenant = 'a1b2c3d4-e5f6-4a8b-9c0d-1e2f3a4b5c6d';
  const otherTenant = 'b2c3d4e5-f6a7-4b8c-9d0e-2f3a4b5c6d7e';
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
  tearDown(() => local.close());

  Future<Database> db() => local.database;
  Future<List<Map<String, Object?>>> outbox() async =>
      (await db()).query('sync_outbox', orderBy: 'outbox_id ASC');

  Map<String, Object?> sg(
    String id,
    String name, {
    String type = SupportGroupType.primerosAuxilios,
    double? gLat,
    double? gLng,
    bool active = true,
    bool deleted = false,
    String tenantId = tenant,
  }) =>
      {
        'id': id,
        'tenant_id': tenantId,
        'name': name,
        'group_type': type,
        'description': 'Descripción $name',
        'contact_phone': '+51 900 000 001',
        'meeting_point': 'Parque central',
        'lat': gLat,
        'lng': gLng,
        'coordinator_user_id': me,
        'is_active': active,
        'is_deleted': deleted,
        'created_at': '2026-11-07T10:00:00+00:00',
        'server_updated_at': '2026-11-07T10:00:00+00:00',
        'updated_at': '2026-11-07T10:00:00+00:00',
      };

  MockClient pullWith(List<Map<String, Object?>> groups) => MockClient((req) async {
        expect(req.url.path, '/api/v1/sync/pull');
        return http.Response(
          jsonEncode({
            'server_timestamp': '2026-11-07T20:00:00Z',
            'has_more': false,
            'tenant': {'id': tenant, 'is_emergency_active': true},
            'delta': {'support_groups': groups},
          }),
          200,
        );
      });

  group('SQLite v5: tabla support_groups', () {
    test('instalación nueva crea la tabla en v5', () async {
      final d = await db();
      expect(await d.getVersion(), 5);
      final names = (await d.rawQuery("SELECT name FROM sqlite_master WHERE type='table'"))
          .map((r) => r['name'])
          .toSet();
      expect(names, contains('support_groups'));
    });

    test('un teléfono en v4 sube a v5 sin perder sus SOS ni su cola', () async {
      final dir = await Directory.systemTemp.createTemp('mi_barrio_v4');
      final path = '${dir.path}${Platform.pathSeparator}v4.db';
      addTearDown(() async {
        await local.close();
        await dir.delete(recursive: true);
      });
      final v4 = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 4,
          onCreate: (d, _) async {
            for (final sql in SqliteTables.createAll) {
              if (sql == SqliteTables.createSupportGroups ||
                  SqliteTables.indexesV5.contains(sql)) {
                continue;
              }
              await d.execute(sql);
            }
          },
        ),
      );
      await v4.insert('vulnerable_reports', {
        'id': 'sos-1', 'tenant_id': tenant, 'reporter_user_id': me, 'urgency_level': 'CRITICA',
        'vulnerability_type': 'ATENCION_MEDICA', 'description': 'Ayuda', 'lat': lat, 'lng': lng,
        'updated_at': '2026-11-07T10:00:00Z', 'sync_status': 'PENDING',
      });
      await v4.insert('sync_outbox', {
        'tenant_id': tenant, 'target_table': 'vulnerable_reports', 'record_id': 'sos-1',
        'operation': 'UPSERT', 'payload_json': '{}', 'created_at': '2026-11-07T10:00:00Z',
      });
      await v4.close();

      await local.resetForTesting(path: path);
      final d = await db();
      expect(await d.getVersion(), SqliteTables.schemaVersion);
      expect((await d.query('vulnerable_reports')).single['id'], 'sos-1');
      expect(await d.query('sync_outbox'), hasLength(1));
      expect(await d.query('support_groups'), isEmpty);
    });
  });

  group('Grupos de apoyo: pull y lectura sin red', () {
    test('el pull los guarda (booleanos 1/0, sin ubicación permitido)', () async {
      final result = await SyncWorker(baseUrl: 'http://api', client: pullWith([
        sg('g1', 'Brigada Centro', gLat: lat + 0.001, gLng: lng),
        sg('g2', 'Olla común', type: SupportGroupType.alimentos),
      ])).pullRemoteChanges(tenant);

      expect(result.success, isTrue);
      final rows = await (await db()).query('support_groups', orderBy: 'id');
      expect(rows, hasLength(2));
      expect(rows.first['is_active'], 1);
      expect(rows.first['sync_status'], SqliteTables.syncSynced);
      expect(rows.last['lat'], isNull);
      expect(rows.first.containsKey('server_updated_at'), isFalse);
    });

    test('se ven SIN internet, del más cercano al más lejano', () async {
      await SyncWorker(baseUrl: 'http://api', client: pullWith([
        sg('lejos', 'Albergue Norte', type: SupportGroupType.albergue, gLat: lat + 0.02, gLng: lng),
        sg('cerca', 'Brigada Centro', gLat: lat + 0.001, gLng: lng),
        sg('sin-ubicacion', 'Apoyo emocional', type: SupportGroupType.saludMental),
      ])).pullRemoteChanges(tenant);

      // Se corta la señal: el siguiente pull falla pero los grupos siguen ahí.
      final offline = MockClient((_) async => throw const SocketException('Sin señal'));
      expect((await SyncWorker(baseUrl: 'http://api', client: offline).pullRemoteChanges(tenant)).success,
          isFalse);

      final ds = SupportGroupsSqliteDatasource();
      final groups = await ds.activeGroups(tenant, lat: lat, lng: lng);
      expect(groups.map((g) => g.id), ['cerca', 'lejos', 'sin-ubicacion']);
      expect(groups.first.distanceKm, closeTo(0.11, 0.02));
      expect(groups.last.distanceKm, isNull);
      expect(groups.first.typeLabel, 'Primeros auxilios');
      expect(groups.first.hasPhone, isTrue);

      final byName = await ds.activeGroups(tenant);
      expect(byName.map((g) => g.name), ['Albergue Norte', 'Apoyo emocional', 'Brigada Centro']);
      expect((await ds.activeGroups(tenant, groupType: SupportGroupType.albergue)).single.id, 'lejos');
      expect(await ds.countActive(tenant), 3);
    });

    test('inactivos, borrados y de otro barrio no se muestran; un cambio posterior se aplica', () async {
      await SyncWorker(baseUrl: 'http://api', client: pullWith([
        sg('g1', 'Brigada'),
        sg('g2', 'Inactivo', active: false),
        sg('g3', 'Borrado', deleted: true),
        sg('g4', 'De otro barrio', tenantId: otherTenant),
      ])).pullRemoteChanges(tenant);
      final ds = SupportGroupsSqliteDatasource();
      expect((await ds.activeGroups(tenant)).map((g) => g.id), ['g1']);
      expect(await (await db()).query('support_groups', where: 'id = ?', whereArgs: ['g4']), isEmpty);

      // La junta desactiva la brigada: el siguiente pull lo refleja.
      await SyncWorker(baseUrl: 'http://api', client: pullWith([sg('g1', 'Brigada', active: false)]))
          .pullRemoteChanges(tenant);
      expect(await ds.activeGroups(tenant), isEmpty);
      expect(await ds.countActive(tenant), 0);
    });
  });

  group('Tutorial: se muestra solo la primera vez', () {
    test('marcar → visto, encola solo la bandera, y no repite', () async {
      final tutorial = TutorialProgress();
      expect(await tutorial.isCompleted(me), isFalse);

      await tutorial.markCompleted(tenantId: tenant, userId: me);
      expect(await tutorial.isCompleted(me), isTrue);

      final queued = await outbox();
      expect(queued, hasLength(1));
      expect(queued.single['target_table'], 'users');
      final payload = jsonDecode(queued.single['payload_json'] as String) as Map;
      expect(payload.keys.toSet(), {'id', 'tutorial_completed', 'updated_at'});
      expect(payload['tutorial_completed'], isTrue);

      await tutorial.markCompleted(tenantId: tenant, userId: me);
      expect(await outbox(), hasLength(1));
    });

    test('no se repite tras CERRAR y REABRIR la app', () async {
      final dir = await Directory.systemTemp.createTemp('mi_barrio_tutorial');
      final path = '${dir.path}${Platform.pathSeparator}app.db';
      addTearDown(() async {
        await local.close();
        await dir.delete(recursive: true);
      });
      await local.resetForTesting(path: path);
      await TutorialProgress().markCompleted(tenantId: tenant, userId: me);
      await local.close(); // la app se cierra

      await local.resetForTesting(path: path); // la app se abre de nuevo
      expect(await TutorialProgress().isCompleted(me), isTrue);
    });

    test('no se repite tras cerrar sesión (se borra el perfil y la cola, no la bandera)', () async {
      await ProfileSync().seedFromLogin(
          userId: me, tenantId: tenant, fullName: 'Rosa', role: 'VECINO', centerLat: lat, centerLng: lng);
      await TutorialProgress().markCompleted(tenantId: tenant, userId: me);
      await SyncOutboxDao().clearUserData(tenantId: tenant, userId: me); // cerrar sesión

      expect(await (await db()).query('users'), isEmpty);
      expect(await TutorialProgress().isCompleted(me), isTrue);
    });

    test('con perfil: la fila queda PENDING y el push la deja SYNCED', () async {
      await ProfileSync().seedFromLogin(
          userId: me, tenantId: tenant, fullName: 'Rosa', role: 'VECINO', centerLat: lat, centerLng: lng);
      await TutorialProgress().markCompleted(tenantId: tenant, userId: me);
      var row = (await (await db()).query('users')).single;
      expect(row['tutorial_completed'], 1);
      expect(row['sync_status'], SqliteTables.syncPending);

      late Map<String, dynamic> sent;
      final client = MockClient((req) async {
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({'processed_record_ids': [me], 'rejected': []}), 200);
      });
      await SyncWorker(baseUrl: 'http://api', client: client).pushLocalChanges(tenant);

      final mutation = (sent['mutations'] as List).single as Map;
      expect(mutation['record_id'], me);
      expect((mutation['payload'] as Map)['tutorial_completed'], isTrue);
      row = (await (await db()).query('users')).single;
      expect(row['sync_status'], SqliteTables.syncSynced);
    });

    test('guardar el perfil después NO des-marca el tutorial', () async {
      await TutorialProgress().markCompleted(tenantId: tenant, userId: me);
      final saved = await ProfileLocalStorage().saveProfile(
          userId: me, tenantId: tenant, fullName: 'Rosa Quispe', homeLat: lat, homeLng: lng);
      expect(saved.tutorialCompleted, isTrue);
      final last = jsonDecode((await outbox()).last['payload_json'] as String) as Map;
      expect(last['tutorial_completed'], isTrue);
    });
  });

  group('Perfil propio al iniciar sesión (rol real)', () {
    Map<String, Object?> serverProfile({
      String role = 'COMERCIANTE',
      bool tutorial = false,
      String name = 'Luis Ramos',
    }) =>
        {
          'id': me,
          'tenant_id': tenant,
          'full_name': name,
          'email': 'luis@barrio.pe',
          'role': role,
          'phone': '+51900000002',
          'address_reference': 'Frente al parque',
          'home_lat': lat,
          'home_lng': lng,
          'tutorial_completed': tutorial,
          'whatsapp': '+51900000002',
          'facebook_url': null,
          'instagram_url': null,
          'photo_b64': null,
          'publisher_type': 'BODEGA',
          'publisher_category': null,
          'publisher_name': 'Bodega Luis',
          'updated_at': '2026-11-07T12:00:00+00:00',
        };

    ProfileSync syncWith(MockClient client) =>
        ProfileSync(api: ApiClient(baseUrl: 'http://api', client: client));

    test('seed sin red: un COMERCIANTE ya ve "Ofrecer servicio"', () async {
      expect((await loadMerchantProfile(me, tenantId: tenant)).isMerchant, isFalse);
      await ProfileSync().seedFromLogin(userId: me, tenantId: tenant, fullName: 'Luis Ramos',
          role: 'COMERCIANTE', centerLat: lat, centerLng: lng);

      expect((await loadMerchantProfile(me, tenantId: tenant)).isMerchant, isTrue);
      final profile = await ProfileLocalStorage().getProfile(me);
      expect(profile!.fullName, 'Luis Ramos');
      expect(profile.roleLabel, 'Comerciante');
      expect(await outbox(), isEmpty); // no se sube nada
    });

    test('el servidor completa el perfil (teléfono, negocio, tutorial)', () async {
      final client = MockClient((req) async {
        expect(req.url.path, '/api/v1/users/me');
        expect(req.headers['X-Tenant-ID'], tenant);
        return http.Response(jsonEncode(serverProfile(tutorial: true)), 200);
      });
      final saved = await syncWith(client).refreshFromServer(tenantId: tenant, userId: me);

      expect(saved, isNotNull);
      final profile = (await ProfileLocalStorage().getProfile(me))!;
      expect(profile.phone, '+51900000002');
      expect(profile.publisherName, 'Bodega Luis');
      expect(profile.role, 'COMERCIANTE');
      expect(profile.syncStatus, SqliteTables.syncSynced);
      expect(await TutorialProgress().isCompleted(me), isTrue, reason: 'visto en otro teléfono');
      expect(await outbox(), isEmpty);
    });

    test('no pisa cambios del perfil hechos sin internet (solo rol y tutorial)', () async {
      await ProfileLocalStorage().saveProfile(
          userId: me, tenantId: tenant, fullName: 'Luis R. (editado offline)', homeLat: lat, homeLng: lng);
      final client = MockClient((_) async => http.Response(jsonEncode(serverProfile(tutorial: true)), 200));
      await syncWith(client).refreshFromServer(tenantId: tenant, userId: me);

      final profile = (await ProfileLocalStorage().getProfile(me))!;
      expect(profile.fullName, 'Luis R. (editado offline)');
      expect(profile.syncStatus, SqliteTables.syncPending);
      expect(profile.role, 'COMERCIANTE');
      expect(profile.tutorialCompleted, isTrue);
    });

    test('visto en el teléfono pero no en el servidor → se vuelve a enviar', () async {
      await TutorialProgress().markCompleted(tenantId: tenant, userId: me);
      await SyncOutboxDao().clearUserData(tenantId: tenant, userId: me); // se perdió la cola
      expect(await outbox(), isEmpty);

      final client = MockClient((_) async => http.Response(jsonEncode(serverProfile()), 200));
      await syncWith(client).refreshFromServer(tenantId: tenant, userId: me);

      final queued = await outbox();
      expect(queued, hasLength(1));
      expect((jsonDecode(queued.single['payload_json'] as String) as Map)['tutorial_completed'], isTrue);
      expect((await ProfileLocalStorage().getProfile(me))!.tutorialCompleted, isTrue);
    });

    test('sin red, error o perfil de otra persona → null y no cambia nada', () async {
      await ProfileSync().seedFromLogin(
          userId: me, tenantId: tenant, fullName: 'Rosa', role: 'VECINO', centerLat: lat, centerLng: lng);
      final before = (await (await db()).query('users')).single;

      for (final client in [
        MockClient((_) async => throw const SocketException('Sin señal')),
        MockClient((_) async => http.Response('error', 500)),
        MockClient((_) async => http.Response(
            jsonEncode({...serverProfile(), 'id': '00000000-0000-4000-8000-000000000000'}), 200)),
        MockClient((_) async => http.Response(jsonEncode({'id': me}), 200)),
      ]) {
        expect(await syncWith(client).refreshFromServer(tenantId: tenant, userId: me), isNull);
      }
      expect((await (await db()).query('users')).single, before);
    });

    test('login real (AuthRepositoryImpl): guarda rol y perfil; sin perfil igual entra', () async {
      final authClient = MockClient((req) async => http.Response(
            jsonEncode({
              'access_token': 'token-de-prueba',
              'token_type': 'bearer',
              'user': {
                'id': me,
                'tenant_id': tenant,
                'full_name': 'Luis Ramos',
                'email': 'luis@barrio.pe',
                'role': 'COMERCIANTE',
                'tenant': {
                  'id': tenant, 'name': 'Barrio Centro Piura', 'join_code': 'BARRIO-01',
                  'center_lat': lat, 'center_lng': lng, 'is_emergency_active': false,
                },
              },
            }),
            200,
          ));
      final repo = AuthRepositoryImpl(
        remote: AuthRemoteDatasource(baseUrl: 'http://api', client: authClient),
        profileSync: syncWith(MockClient((_) async => throw const SocketException('Sin señal'))),
      );

      final user = await repo.login(email: 'luis@barrio.pe', password: 'clave-segura');
      expect(user.id, me);
      expect((await loadMerchantProfile(me, tenantId: tenant)).isMerchant, isTrue);
      expect((await ProfileLocalStorage().getProfile(me))!.fullName, 'Luis Ramos');
    });
  });
}
