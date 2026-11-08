import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mi_barrio_app/core/auth/auth_session_store.dart';
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
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Checkpoint 1 de punta a punta contra el backend REAL (FastAPI + PostgreSQL):
/// publicar sin red → PENDING → vuelve internet → la fila está en PostgreSQL
/// con el mismo UUID.
///
/// Requiere backend, migraciones y secreto JWT configurados. Si faltan,
/// la prueba de integración se salta.
///   flutter test test/e2e --dart-define=API_BASE_URL=http://localhost:8000
void main() {
  const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );
  const superAdminEmail = String.fromEnvironment('E2E_SUPER_ADMIN_EMAIL');
  const superAdminPassword = String.fromEnvironment('E2E_SUPER_ADMIN_PASSWORD');
  const centerLat = -5.1945;
  const centerLng = -80.6328;

  final local = LocalDatabase.instance;
  var backendReady = false;
  var backendReadinessMessage = 'Backend no disponible';
  var tenant = '';
  var joinCode = '';
  var neighborId = '';
  var neighborToken = '';
  var merchantId = '';
  var merchantToken = '';
  var providerId = '';
  var providerToken = '';

  Future<Map<String, String>?> registerUser(String role) async {
    final email = 'e2e-${const Uuid().v4()}@example.test';
    final response = await http.post(
      Uri.parse('$baseUrl/api/v1/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'full_name': 'Usuario E2E',
        'email': email,
        'password': 'MiBarrio-e2e-123',
        'role': role,
        'join_code': joinCode,
        'accept_terms': true,
      }),
    );
    if (response.statusCode != 201) {
      backendReadinessMessage =
          'Autenticación no disponible (HTTP ${response.statusCode})';
      return null;
    }
    final auth = jsonDecode(response.body) as Map<String, dynamic>;
    final user = auth['user'] as Map<String, dynamic>;
    return {
      'id': user['id'] as String,
      'token': auth['access_token'] as String,
    };
  }

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    try {
      final r = await http
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 3));
      if (r.statusCode == 200 &&
          superAdminEmail.isNotEmpty &&
          superAdminPassword.isNotEmpty) {
        final health = jsonDecode(r.body) as Map<String, dynamic>;
        final healthData = health['data'] as Map<String, dynamic>?;
        if (healthData?['migrations_up_to_date'] == true) {
          final adminLogin = await http.post(
            Uri.parse('$baseUrl/api/v1/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': superAdminEmail,
              'password': superAdminPassword,
            }),
          );
          if (adminLogin.statusCode == 200) {
            final adminToken =
                (jsonDecode(adminLogin.body) as Map<String, dynamic>)['access_token']
                    as String;
            final unique = const Uuid().v4();
            final neighborhoodResponse = await http.post(
              Uri.parse('$baseUrl/api/v1/platform/neighborhoods'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $adminToken',
              },
              body: jsonEncode({
                'neighborhood_name': 'E2E $unique',
                'admin_full_name': 'Administrador E2E',
                'admin_email': 'e2e-admin-$unique@example.test',
                'admin_password': 'MiBarrio-e2e-admin-123',
                'center_lat': centerLat,
                'center_lng': centerLng,
              }),
            );
            if (neighborhoodResponse.statusCode == 201) {
              final created = jsonDecode(neighborhoodResponse.body)
                  as Map<String, dynamic>;
              final neighborhood =
                  created['neighborhood'] as Map<String, dynamic>;
              tenant = neighborhood['id'] as String;
              joinCode = neighborhood['join_code'] as String;
              final neighbor = await registerUser('VECINO');
              final merchant = await registerUser('COMERCIANTE');
              final provider = await registerUser('COMERCIANTE');
              if (neighbor != null && merchant != null && provider != null) {
                neighborId = neighbor['id']!;
                neighborToken = neighbor['token']!;
                merchantId = merchant['id']!;
                merchantToken = merchant['token']!;
                providerId = provider['id']!;
                providerToken = provider['token']!;
                backendReady = true;
              }
            } else {
              backendReadinessMessage =
                  'No se pudo crear el barrio E2E (HTTP ${neighborhoodResponse.statusCode})';
            }
          } else {
            backendReadinessMessage =
                'No se pudo autenticar el superadministrador E2E';
          }
        } else {
          backendReadinessMessage = 'Faltan migraciones de base de datos';
        }
      } else if (r.statusCode == 200) {
        backendReadinessMessage =
            'Define E2E_SUPER_ADMIN_EMAIL y E2E_SUPER_ADMIN_PASSWORD para crear un barrio aislado';
      }
    } catch (error) {
      backendReadinessMessage = 'Falló la preparación del backend E2E: $error';
    }
  });
  setUp(() => local.resetForTesting(path: inMemoryDatabasePath));
  tearDown(() async {
    await SyncCoordinator.instance.stop();
    await local.close();
  });

  test('publicar sin red y reconectar sube la fila a PostgreSQL', () async {
    if (!backendReady) {
      markTestSkipped('$backendReadinessMessage en $baseUrl');
      return;
    }
    await AuthSessionStore.instance.save({'token': neighborToken});

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
      authorUserId: neighborId,
      modality: SolidarityModality.prestamoHerramienta,
      title: 'Checkpoint 1 ${DateTime.now().toUtc().toIso8601String()}',
      lat: centerLat,
      lng: centerLng,
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
      headers: {
        'X-Tenant-ID': tenant,
        'Authorization': 'Bearer $neighborToken',
      },
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
    if (!backendReady) {
      markTestSkipped('$backendReadinessMessage en $baseUrl');
      return;
    }
    await AuthSessionStore.instance.save({'token': merchantToken});
    final headers = {
      'Content-Type': 'application/json',
      'X-Tenant-ID': tenant,
      'Authorization': 'Bearer $merchantToken',
    };
    final stamp = DateTime.now().toUtc().toIso8601String();

    // Otro vecino (otro teléfono) publica un oficio que llega al servidor.
    final providerHeaders = {
      ...headers,
      'Authorization': 'Bearer $providerToken',
    };
    final created = await http.post(
      Uri.parse('$baseUrl/api/v1/services'),
      headers: providerHeaders,
      body: jsonEncode({
        'provider_user_id': providerId,
        'category': ServiceCategory.electricidad,
        'title': 'E2E Electricista $stamp',
        'description': 'Creado por otro teléfono',
        'lat': centerLat,
        'lng': centerLng,
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
      providerUserId: merchantId,
      category: ServiceCategory.gasfiteria,
      title: 'E2E Gasfitero $stamp',
      lat: centerLat,
      lng: centerLng,
      publisherType: 'EMPRENDEDOR',
      publisherName: 'Gasfitería E2E',
    );
    final rating = await EndorsementsSqliteDatasource().rateService(
      tenantId: tenant,
      serviceId: otherServiceId,
      endorserUserId: merchantId,
      rating: 4,
      shortComment: 'Llegó rápido',
    );
    final profileUserId = merchantId;
    await ProfileLocalStorage().saveProfile(
      userId: profileUserId,
      tenantId: tenant,
      fullName: 'Vecina E2E',
      phone: '987654321',
      homeLat: centerLat,
      homeLng: centerLng,
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
    expect(remoteOther['endorsements_count'], 1);

    // 4. El pull dejó en el teléfono el oficio del vecino con su promedio.
    final localOther = await db.query(
      'local_services',
      where: 'id = ?',
      whereArgs: [otherServiceId],
    );
    expect(localOther, hasLength(1));
    expect(localOther.first['rating_avg'], 4.0);
    expect(localOther.first['endorsements_count'], 1);
    expect(localOther.first['sync_status'], 'SYNCED');

    // 5. Retirar un visto bueno también se sincroniza y recalcula el contador.
    await EndorsementsSqliteDatasource().removeEndorsement(
      tenantId: tenant,
      serviceId: otherServiceId,
      endorserUserId: merchantId,
    );
    await SyncCoordinator.instance.syncNow();
    final afterRemoval = await http.get(
      Uri.parse('$baseUrl/api/v1/services'),
      headers: headers,
    );
    final servicesAfterRemoval = (jsonDecode(afterRemoval.body) as List)
        .cast<Map<String, dynamic>>();
    final remoteAfterRemoval = servicesAfterRemoval.firstWhere(
      (s) => s['id'] == otherServiceId,
    );
    expect(remoteAfterRemoval['endorsements_count'], 0);
    expect(remoteAfterRemoval['rating_avg'], isNull);

    // ignore: avoid_print
    print(
      'Servicios/vistos buenos/perfil OK: ${mine.id}, $otherServiceId, $profileUserId',
    );
    await connection.close();
  });
}
