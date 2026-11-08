import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mi_barrio_app/core/auth/auth_session_store.dart';
import 'package:mi_barrio_app/core/barrio_context/emergency_mode_provider.dart';
import 'package:mi_barrio_app/core/database_sqlite/sqlite_database.dart';
import 'package:mi_barrio_app/core/database_sqlite/sqlite_tables.dart';
import 'package:mi_barrio_app/core/database_sqlite/sync_outbox_dao.dart';
import 'package:mi_barrio_app/core/sync_manager/sync_worker.dart';
import 'package:mi_barrio_app/features/emergency_support/data/repositories/emergency_repository_impl.dart';
import 'package:mi_barrio_app/features/emergency_support/domain/entities/vulnerable_report_entity.dart';
import 'package:mi_barrio_app/features/proximity_services/data/datasources/services_sqlite_ds.dart';
import 'package:mi_barrio_app/features/proximity_services/data/models/service_model.dart';
import 'package:mi_barrio_app/features/solidarity_network/data/datasources/solidarity_sqlite_ds.dart';
import 'package:mi_barrio_app/features/solidarity_network/data/models/solidarity_post_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Brechas encontradas en la prueba de punta a punta online/offline (sáb 7, noche).
/// La versión contra el servidor real está en test/e2e/online_offline_e2e_test.dart.
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
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await local.resetForTesting(path: inMemoryDatabasePath);
    EmergencyModeProvider.instance.resetForTesting();
  });
  tearDown(() async {
    EmergencyModeProvider.instance.resetForTesting();
    await AuthSessionStore.instance.clear();
    await local.close();
  });

  Future<Database> db() => local.database;

  Future<void> loginAs(String tenantId) => AuthSessionStore.instance.save({
        'id': me, 'tenant_id': tenantId, 'role': 'VECINO', 'token': 't', 'full_name': 'Rosa',
      });

  MockClient pullWithEmergency(bool active) => MockClient((_) async => http.Response(
        jsonEncode({
          'server_timestamp': '2026-11-07T20:00:00Z',
          'tenant': {'id': tenant, 'is_emergency_active': active},
          'delta': <String, Object>{},
        }),
        200,
      ));

  group('Brecha 1: emergencia de la junta tras reiniciar SIN señal', () {
    test('la bandera del barrio se guarda y vuelve al abrir la app', () async {
      await loginAs(tenant);
      await SyncWorker(baseUrl: 'http://api', client: pullWithEmergency(true)).pullRemoteChanges(tenant);
      expect(EmergencyModeProvider.instance.isActive.value, isTrue);

      EmergencyModeProvider.instance.resetForTesting(); // la app se cierra
      await EmergencyModeProvider.instance.load(); // y se abre sin señal
      expect(EmergencyModeProvider.instance.isActive.value, isTrue);
      expect(EmergencyModeProvider.instance.isActive.value, isTrue);
    });

    test('cuando la junta la apaga, al reabrir sigue apagada', () async {
      await loginAs(tenant);
      await SyncWorker(baseUrl: 'http://api', client: pullWithEmergency(true)).pullRemoteChanges(tenant);
      await SyncWorker(baseUrl: 'http://api', client: pullWithEmergency(false)).pullRemoteChanges(tenant);
      EmergencyModeProvider.instance.resetForTesting();
      await EmergencyModeProvider.instance.load();
      expect(EmergencyModeProvider.instance.isActive.value, isFalse);
    });

    test('no se hereda a un vecino de OTRO barrio en el mismo teléfono', () async {
      await loginAs(tenant);
      await SyncWorker(baseUrl: 'http://api', client: pullWithEmergency(true)).pullRemoteChanges(tenant);
      await loginAs(otherTenant); // otra cuenta, otro barrio
      EmergencyModeProvider.instance.resetForTesting();
      await EmergencyModeProvider.instance.load();
      expect(EmergencyModeProvider.instance.isActive.value, isFalse);
    });

    test('sin sesión guardada no activa nada', () async {
      await loginAs(tenant);
      await SyncWorker(baseUrl: 'http://api', client: pullWithEmergency(true)).pullRemoteChanges(tenant);
      await AuthSessionStore.instance.clear();
      EmergencyModeProvider.instance.resetForTesting();
      await EmergencyModeProvider.instance.load();
      expect(EmergencyModeProvider.instance.isActive.value, isFalse);
    });
  });

  group('Brecha 2: rechazos del servidor', () {
    Future<LocalServiceModel> offer() => ServicesSqliteDatasource().insertService(
        tenantId: tenant, providerUserId: me, category: ServiceCategory.clases,
        title: 'Clases', lat: lat, lng: lng);

    MockClient rejectWith(String reason) => MockClient((req) async {
          final body = jsonDecode(req.body) as Map<String, dynamic>;
          final m = (body['mutations'] as List).single as Map;
          return http.Response(
            jsonEncode({
              'processed_record_ids': <String>[],
              'rejected': [
                {'target_table': m['target_table'], 'record_id': m['record_id'], 'reason': reason},
              ],
            }),
            200,
          );
        });

    test('un rechazo del servidor sale como "Sin enviar"', () async {
      final svc = await offer();
      final result = await SyncWorker(baseUrl: 'http://api',
              client: rejectWith('ValueError: solo un comerciante puede sincronizar servicios'))
          .pushLocalChanges(tenant);

      expect(result.success, isFalse);
      expect(await (await db()).query('sync_outbox'), isEmpty);
      final row = (await (await db()).query('local_services', where: 'id = ?', whereArgs: [svc.id])).single;
      expect(row['sync_status'], SqliteTables.syncFailed);
    });
  });

  group('Brecha 3: cerrar sesión en un teléfono compartido', () {
    test('se borra lo privado y lo no enviado; lo publicado (SYNCED) se queda', () async {
      final d = await db();
      // Favor ya publicado (llegó del servidor) y uno escrito sin señal.
      await d.insert(SolidarityPostModel.table, SolidarityPostModel(
        id: 'publicado', tenantId: tenant, authorUserId: me, flowType: SolidarityFlowType.solicitoAyuda,
        modality: SolidarityModality.prestamoHerramienta, title: 'Escalera', lat: lat, lng: lng,
        updatedAt: '2026-11-07T10:00:00Z', syncStatus: SqliteTables.syncSynced).toSqlite());
      final borrador = await SolidaritySqliteDatasource().publishInThreeClicks(
          tenantId: tenant, authorUserId: me, modality: SolidarityModality.donacionMaterial,
          title: 'Frazadas', lat: lat, lng: lng);
      final sosSinEnviar = await EmergencyRepositoryImpl().createSos(
          tenantId: tenant, reporterUserId: me, vulnerabilityType: VulnerabilityType.faltaSuministros,
          urgencyLevel: UrgencyLevel.media, description: 'Agua', lat: lat, lng: lng);
      await d.insert('users', {
        'id': me, 'tenant_id': tenant, 'full_name': 'Rosa', 'home_lat': lat, 'home_lng': lng,
        'updated_at': '2026-11-07T10:00:00Z', 'sync_status': SqliteTables.syncSynced,
      });

      await SyncOutboxDao().clearUserData(tenantId: tenant, userId: me);

      final posts = (await d.query(SolidarityPostModel.table)).map((r) => r['id']);
      expect(posts, contains('publicado'));
      expect(posts, isNot(contains(borrador.id)));
      expect(await d.query('vulnerable_reports', where: 'id = ?', whereArgs: [sosSinEnviar.id]), isEmpty,
          reason: 'antes quedaba "Pendiente" para siempre sin cola');
      expect(await d.query('users'), isEmpty, reason: 'el perfil es privado');
      expect(await d.query('sync_outbox'), isEmpty);
    });
  });
}
