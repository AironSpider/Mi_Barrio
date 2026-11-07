import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mi_barrio_app/core/barrio_context/tenant_session.dart';
import 'package:mi_barrio_app/core/database_sqlite/sqlite_database.dart';
import 'package:mi_barrio_app/core/network/connectivity_monitor.dart';
import 'package:mi_barrio_app/core/sync_manager/sync_coordinator.dart';
import 'package:mi_barrio_app/core/sync_manager/sync_worker.dart';
import 'package:mi_barrio_app/features/solidarity_network/data/datasources/solidarity_sqlite_ds.dart';
import 'package:mi_barrio_app/features/solidarity_network/data/models/solidarity_post_model.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Checkpoint 1 de punta a punta contra el backend REAL (FastAPI + PostgreSQL):
/// publicar sin red → PENDING → vuelve internet → la fila está en PostgreSQL
/// con el mismo UUID.
///
/// Requiere el backend levantado. Si no responde, la prueba se salta.
///   flutter test test/e2e --dart-define=API_BASE_URL=http://localhost:8000
void main() {
  const baseUrl = String.fromEnvironment('API_BASE_URL',
      defaultValue: 'http://localhost:8000');
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
    Future<String?> status() async => (await db.query('solidarity_posts',
            where: 'id = ?', whereArgs: [post.id]))
        .first['sync_status'] as String?;
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
    final r = await http.get(Uri.parse('$baseUrl/api/v1/sync/pull'),
        headers: {'X-Tenant-ID': tenant});
    expect(r.statusCode, 200);
    final remote = (jsonDecode(r.body)['delta']['solidarity_posts'] as List)
        .cast<Map<String, dynamic>>()
        .where((p) => p['id'] == post.id);
    expect(remote, hasLength(1), reason: 'La fila ${post.id} no está en PostgreSQL');
    expect(remote.first['title'], post.title);

    // ignore: avoid_print
    print('Checkpoint 1 OK: ${post.id} está en PostgreSQL');
    await connection.close();
  });
}
