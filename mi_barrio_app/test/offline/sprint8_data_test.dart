import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mi_barrio_app/core/barrio_context/emergency_mode_provider.dart';
import 'package:mi_barrio_app/core/database_sqlite/sqlite_database.dart';
import 'package:mi_barrio_app/core/database_sqlite/sqlite_tables.dart';
import 'package:mi_barrio_app/core/database_sqlite/sync_outbox_dao.dart';
import 'package:mi_barrio_app/core/sync_manager/sync_worker.dart';
import 'package:mi_barrio_app/features/auth_barrio/data/repositories/auth_repository_impl.dart';
import 'package:mi_barrio_app/features/auth_barrio/data/models/user_model.dart';
import 'package:mi_barrio_app/features/emergency_support/data/repositories/emergency_repository_impl.dart';
import 'package:mi_barrio_app/features/emergency_support/domain/entities/vulnerable_report_entity.dart';
import 'package:mi_barrio_app/features/solidarity_network/data/datasources/solidarity_sqlite_ds.dart';
import 'package:mi_barrio_app/features/solidarity_network/data/models/solidarity_post_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  const tenant = 'a1b2c3d4-e5f6-4a8b-9c0d-1e2f3a4b5c6d';
  const me = '5f3a2c1b-1234-4abc-9def-0123456789ab';
  const otra = '9a8b7c6d-5e4f-4a3b-8c2d-1e0f9a8b7c6d';
  const lat = -5.1945;
  const lng = -80.6328;
  final local = LocalDatabase.instance;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await local.resetForTesting(path: inMemoryDatabasePath);
    EmergencyModeProvider.instance.resetForTesting();
  });
  tearDown(() => local.close());

  Future<List<Map<String, Object?>>> outbox() async =>
      (await local.database).query('sync_outbox', orderBy: 'outbox_id');

  group('SOS en SQLite (sin red)', () {
    test('crear SOS: fila PENDING + mutación con formato del contrato', () async {
      final repo = EmergencyRepositoryImpl();
      final sos = await repo.createSos(
        tenantId: tenant,
        reporterUserId: me,
        vulnerabilityType: VulnerabilityType.atencionMedica,
        urgencyLevel: UrgencyLevel.critica,
        description: '  ',
        lat: lat,
        lng: lng,
      );
      final saved = await repo.activeReports(tenant);
      expect(saved.single.id, sos.id);
      expect(saved.single.isPending, isTrue);
      expect(saved.single.description, VulnerabilityType.labels[VulnerabilityType.atencionMedica]); // nunca vacío
      final payload = jsonDecode((await outbox()).single['payload_json'] as String) as Map;
      expect(payload['reporter_user_id'], me);
      expect(payload['is_deleted'], isFalse);
      expect(payload.containsKey('tenant_id'), isFalse);
      expect(payload.containsKey('sync_status'), isFalse);
    });

    test('rechaza datos fuera del contrato sin guardar nada', () async {
      final repo = EmergencyRepositoryImpl();
      Future<void> crear({String tipo = VulnerabilityType.adultoMayorSolo, String urg = UrgencyLevel.alta, double la = lat}) =>
          repo.createSos(tenantId: tenant, reporterUserId: me, vulnerabilityType: tipo, urgencyLevel: urg, description: 'x', lat: la, lng: lng);
      await expectLater(crear(tipo: 'HACK'), throwsArgumentError);
      await expectLater(crear(urg: 'URGENTISIMA'), throwsArgumentError);
      await expectLater(crear(la: 999), throwsArgumentError);
      expect(await repo.activeReports(tenant), isEmpty);
      expect(await outbox(), isEmpty);
    });

    test('"Voy en camino" en el SOS de otra persona; nunca en el propio', () async {
      final repo = EmergencyRepositoryImpl();
      final ajeno = await repo.createSos(tenantId: tenant, reporterUserId: otra, vulnerabilityType: VulnerabilityType.movilidadReducida, urgencyLevel: UrgencyLevel.alta, description: 'silla de ruedas', lat: lat, lng: lng);
      final propio = await repo.createSos(tenantId: tenant, reporterUserId: me, vulnerabilityType: VulnerabilityType.faltaSuministros, urgencyLevel: UrgencyLevel.media, description: 'agua', lat: lat, lng: lng);

      final updated = await repo.offerHelp(tenantId: tenant, reportId: ajeno.id, helperUserId: me);
      expect(updated.status, ReportStatus.vecinosEnCamino);
      expect(updated.helperUserId, me);
      final last = jsonDecode((await outbox()).last['payload_json'] as String) as Map;
      expect(last['status'], 'VECINOS_EN_CAMINO');
      expect(last['helper_user_id'], me);
      expect(last['reporter_user_id'], otra, reason: 'el autor no cambia');

      await expectLater(repo.offerHelp(tenantId: tenant, reportId: propio.id, helperUserId: me), throwsArgumentError);
    });

    test('un teléfono en v3 sube a v4 sin perder datos', () async {
      final db = await local.database;
      expect(await db.getVersion(), SqliteTables.schemaVersion);
      expect(SqliteTables.schemaVersion, greaterThanOrEqualTo(4));
      final names = (await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'")).map((r) => r['name']).toSet();
      expect(names, contains('vulnerable_reports'));
    });
  });

  group('Pull de emergencia', () {
    test('baja los SOS de otros vecinos y la bandera de emergencia del barrio', () async {
      final client = MockClient((req) async => http.Response(
            jsonEncode({
              'server_timestamp': '2026-11-07T16:00:00Z',
              'has_more': false,
              'tenant': {'id': tenant, 'name': 'Demo', 'is_emergency_active': true, 'registered': true},
              'delta': {
                'vulnerable_reports': [
                  {
                    'id': 'c0ffee00-0000-4000-8000-000000000010',
                    'tenant_id': tenant,
                    'reporter_user_id': otra,
                    'urgency_level': 'CRITICA',
                    'vulnerability_type': 'ATENCION_MEDICA',
                    'description': 'Dolor de pecho',
                    'lat': lat,
                    'lng': lng,
                    'status': 'PENDIENTE_APOYO',
                    'helper_user_id': null,
                    'is_deleted': false,
                    'updated_at': '2026-11-07T15:59:00+00:00',
                    'server_updated_at': '2026-11-07T15:59:01+00:00',
                  },
                ],
              },
            }),
            200,
          ));
      expect(EmergencyModeProvider.instance.isActive.value, isFalse);
      final result = await SyncWorker(baseUrl: 'http://api', client: client).pullRemoteChanges(tenant);
      expect(result.success, isTrue);
      final reports = await EmergencyRepositoryImpl().activeReports(tenant);
      expect(reports.single.description, 'Dolor de pecho');
      expect(reports.single.isPending, isFalse);
      expect(EmergencyModeProvider.instance.isActive.value, isTrue);
      expect(EmergencyModeProvider.instance.isLockedByTenant.value, isTrue);
    });
  });

  group('Sesión vencida y cambios hechos sin internet', () {
    Future<void> publicarOffline() => SolidaritySqliteDatasource().publishInThreeClicks(
          tenantId: tenant,
          authorUserId: me,
          modality: SolidarityModality.prestamoHerramienta,
          title: 'Post hecho sin internet',
          lat: lat,
          lng: lng,
        );

    UserModel user(String id) => UserModel.fromJson({
          'id': id,
          'tenant_id': tenant,
          'full_name': 'Vecina',
          'role': 'VECINO',
          'access_token': 't',
          'tenant': const <String, dynamic>{},
        });

    test('si vuelve a entrar la MISMA persona, sus cambios pendientes se conservan', () async {
      await publicarOffline();
      final repo = AuthRepositoryImpl();
      await repo.keepPendingDataFor(tenantId: tenant, userId: me);
      await repo.reconcilePendingData(user(me));
      expect(await outbox(), hasLength(1));
      expect(await SolidaritySqliteDatasource().getActivePosts(tenant), hasLength(1));
      expect(await SyncOutboxDao().readPendingOwner(), isNull);
    });

    test('si entra OTRA persona, los pendientes de la anterior se descartan', () async {
      await publicarOffline();
      final repo = AuthRepositoryImpl();
      await repo.keepPendingDataFor(tenantId: tenant, userId: me);
      await repo.reconcilePendingData(user(otra));
      expect(await outbox(), isEmpty);
      expect(await SolidaritySqliteDatasource().getActivePosts(tenant), isEmpty);
    });
  });
}
