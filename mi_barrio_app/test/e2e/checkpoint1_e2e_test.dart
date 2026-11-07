import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mi_barrio_app/core/barrio_context/tenant_session.dart';
import 'package:mi_barrio_app/core/database_sqlite/sqlite_database.dart';
import 'package:mi_barrio_app/core/network/connectivity_monitor.dart';
import 'package:mi_barrio_app/core/sync_manager/sync_coordinator.dart';
import 'package:mi_barrio_app/core/sync_manager/sync_worker.dart';
import 'package:mi_barrio_app/features/profile_me/data/profile_local_storage.dart';
import 'package:mi_barrio_app/features/proximity_services/data/datasources/endorsements_sqlite_ds.dart';
import 'package:mi_barrio_app/features/proximity_services/data/datasources/services_sqlite_ds.dart';
import 'package:mi_barrio_app/features/proximity_services/data/models/service_model.dart';
import 'package:mi_barrio_app/features/solidarity_network/data/datasources/solidarity_sqlite_ds.dart';
import 'package:mi_barrio_app/features/solidarity_network/data/models/solidarity_post_model.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

/// Checkpoint 1 de punta a punta contra el backend REAL (FastAPI + PostgreSQL):
/// publicar sin red → PENDING → vuelve internet → la fila está en PostgreSQL
/// con el mismo UUID.
///
/// Requiere el backend levantado. Si no responde, la prueba se salta.
///   flutter test test/e2e --dart-define=API_BASE_URL=http://localhost:8000
void main() {
  const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );
  const tenant = TenantSession.demoTenantId;
  const me = TenantSession.demoUserId;

  final local = LocalDatabase.instance;
  var backendUp = false;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    try {
      final r = await http
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 3));
      backendUp = r.statusCode == 200;
    } catch (_) {}
  });
  setUp(() => local.resetForTesting(path: inMemoryDatabasePath));
  tearDown(() async {
    await SyncCoordinator.instance.stop();
    await local.close();
  });

  test('publicar sin red y reconectar sube la fila a PostgreSQL', () async {
    if (!backendUp) {
      markTestSkipped('Backend no disponible en $baseUrl');
      return;
    }

    final connection = StreamController<ConnectionStatus>.broadcast();
    var online = false;
    await SyncCoordinator.instance.start(
      worker: SyncWorker(baseUrl: baseUrl),
      connectionChanges: connection.stream,
      isOnline: () => online,
      tenantId: () => tenant,
      interval: const Duration(hours: 1),
      syncImmediately: false,
    );

    // 1. Sin red: se guarda en el teléfono como PENDING.
    final post = await SolidaritySqliteDatasource().publishInThreeClicks(
      tenantId: tenant,
      authorUserId: me,
      modality: SolidarityModality.prestamoHerramienta,
      title: 'Checkpoint 1 ${DateTime.now().toUtc().toIso8601String()}',
      lat: TenantSession.demoCenterLat,
      lng: TenantSession.demoCenterLng,
    );
    await Future<void>.delayed(const Duration(milliseconds: 700));
    final db = await local.database;
    Future<String?> status() async =>
        (await db.query(
              'solidarity_posts',
              where: 'id = ?',
              whereArgs: [post.id],
            )).first['sync_status']
            as String?;
    expect(await status(), 'PENDING');
    expect(SyncCoordinator.instance.phase.value, SyncPhase.offline);

    // 2. Vuelve internet: el coordinador sincroniza solo.
    online = true;
    connection.add(ConnectionStatus.online);
    for (var i = 0; i < 50 && await status() != 'SYNCED'; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    expect(await status(), 'SYNCED');
    expect(await db.query('sync_outbox'), isEmpty);

    // 3. El servidor la devuelve desde PostgreSQL con el mismo UUID.
    final r = await http.get(
      Uri.parse('$baseUrl/api/v1/sync/pull'),
      headers: {'X-Tenant-ID': tenant},
    );
    expect(r.statusCode, 200);
    final remote = (jsonDecode(r.body)['delta']['solidarity_posts'] as List)
        .cast<Map<String, dynamic>>()
        .where((p) => p['id'] == post.id);
    expect(
      remote,
      hasLength(1),
      reason: 'La fila ${post.id} no está en PostgreSQL',
    );
    expect(remote.first['title'], post.title);

    // ignore: avoid_print
    print('Checkpoint 1 OK: ${post.id} está en PostgreSQL');
    await connection.close();
  });

  test('servicios, calificación y perfil offline suben; el pull trae el promedio', () async {
    if (!backendUp) {
      markTestSkipped('Backend no disponible en $baseUrl');
      return;
    }
    final headers = {'Content-Type': 'application/json', 'X-Tenant-ID': tenant};
    final stamp = DateTime.now().toUtc().toIso8601String();

    // Otro vecino (otro teléfono) publica un oficio que llega al servidor.
    final otherProvider = const Uuid().v4();
    final created = await http.post(
      Uri.parse('$baseUrl/api/v1/services'),
      headers: headers,
      body: jsonEncode({
        'provider_user_id': otherProvider,
        'category': ServiceCategory.electricidad,
        'title': 'E2E Electricista $stamp',
        'description': 'Creado por otro teléfono',
        'lat': TenantSession.demoCenterLat,
        'lng': TenantSession.demoCenterLng,
      }),
    );
    expect(created.statusCode, 201, reason: created.body);
    final otherServiceId = jsonDecode(created.body)['id'] as String;

    var online = true;
    final connection = StreamController<ConnectionStatus>.broadcast();
    await SyncCoordinator.instance.start(
      worker: SyncWorker(baseUrl: baseUrl),
      connectionChanges: connection.stream,
      isOnline: () => online,
      tenantId: () => tenant,
      interval: const Duration(hours: 1),
      syncImmediately: false,
    );

    // 0. Con red, el teléfono descarga el oficio del vecino; luego se queda sin red.
    await SyncCoordinator.instance.syncNow();
    final db = await local.database;
    expect(
      await db.query(
        'local_services',
        where: 'id = ?',
        whereArgs: [otherServiceId],
      ),
      hasLength(1),
      reason: 'El pull no trajo el oficio del otro teléfono',
    );
    online = false;
    connection.add(ConnectionStatus.offline);

    // 1. Sin red: publico mi oficio, califico el del vecino y guardo mi perfil.
    final mine = await ServicesSqliteDatasource().insertService(
      tenantId: tenant,
      providerUserId: me,
      category: ServiceCategory.gasfiteria,
      title: 'E2E Gasfitero $stamp',
      lat: TenantSession.demoCenterLat,
      lng: TenantSession.demoCenterLng,
      publisherType: 'EMPRENDEDOR',
      publisherName: 'Gasfitería E2E',
    );
    final rating = await EndorsementsSqliteDatasource().rateService(
      tenantId: tenant,
      serviceId: otherServiceId,
      endorserUserId: me,
      rating: 4,
      shortComment: 'Llegó rápido',
    );
    final simpleEndorsement = await EndorsementsSqliteDatasource().rateService(
      tenantId: tenant,
      serviceId: otherServiceId,
      endorserUserId: const Uuid().v4(),
    );
    final profileUserId = const Uuid().v4();
    await ProfileLocalStorage().saveProfile(
      userId: profileUserId,
      tenantId: tenant,
      fullName: 'Vecina E2E',
      phone: '987654321',
      homeLat: TenantSession.demoCenterLat,
      homeLng: TenantSession.demoCenterLng,
      email: 'vecina.e2e@example.com',
    );
    await Future<void>.delayed(const Duration(milliseconds: 700));
    Future<String?> status(String table, String id) async =>
        (await db.query(
              table,
              where: 'id = ?',
              whereArgs: [id],
            )).first['sync_status']
            as String?;
    expect(await status('local_services', mine.id), 'PENDING');
    expect(await status('neighbor_endorsements', rating.id), 'PENDING');
    expect(
      await status('neighbor_endorsements', simpleEndorsement.id),
      'PENDING',
    );
    expect(await status('users', profileUserId), 'PENDING');

    // 2. Vuelve internet.
    online = true;
    connection.add(ConnectionStatus.online);
    for (var i = 0; i < 50 && (await db.query('sync_outbox')).isNotEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    await SyncCoordinator.instance.syncNow(); // asegura que el pull terminó
    expect(
      await db.query('sync_outbox'),
      isEmpty,
      reason: 'Quedaron mutaciones sin confirmar por el servidor',
    );
    expect(await status('local_services', mine.id), 'SYNCED');
    expect(await status('neighbor_endorsements', rating.id), 'SYNCED');
    expect(
      await status('neighbor_endorsements', simpleEndorsement.id),
      'SYNCED',
    );
    expect(await status('users', profileUserId), 'SYNCED');

    // 3. El servidor tiene mi oficio y recalculó la calificación del vecino.
    final list = await http.get(
      Uri.parse('$baseUrl/api/v1/services'),
      headers: headers,
    );
    final services = (jsonDecode(list.body) as List)
        .cast<Map<String, dynamic>>();
    final remoteMine = services.firstWhere((s) => s['id'] == mine.id);
    expect(remoteMine['publisher_name'], 'Gasfitería E2E');
    final remoteOther = services.firstWhere((s) => s['id'] == otherServiceId);
    expect(remoteOther['rating_avg'], 4.0);
    expect(remoteOther['endorsements_count'], 2);

    // 4. El pull dejó en el teléfono el oficio del vecino con su promedio.
    final localOther = await db.query(
      'local_services',
      where: 'id = ?',
      whereArgs: [otherServiceId],
    );
    expect(localOther, hasLength(1));
    expect(localOther.first['rating_avg'], 4.0);
    expect(localOther.first['endorsements_count'], 2);
    expect(localOther.first['sync_status'], 'SYNCED');

    // ignore: avoid_print
    print(
      'Servicios/calificación/perfil OK: ${mine.id}, $otherServiceId, $profileUserId',
    );
    await connection.close();
  });
}
