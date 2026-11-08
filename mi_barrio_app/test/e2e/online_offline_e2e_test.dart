// Prueba de PUNTA A PUNTA contra el backend real: online → offline → reabrir la
// app sin señal → volver online, con DOS teléfonos (vecina y comerciante) y la junta.
//
// Se salta si no hay servidor de pruebas. Para correrla (PowerShell):
//   $env:E2E_API_URL="http://localhost:8000"; $env:E2E_JOIN_CODE="TEST-XXXX"
//   $env:E2E_ADMIN_EMAIL="..."; $env:E2E_ADMIN_PASSWORD="..."
//   flutter test test/e2e/online_offline_e2e_test.dart
// (barrio de prueba: scripts/_test_env.py → isolated_neighborhood; nunca BARRIO-01)
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mi_barrio_app/core/auth/auth_session_store.dart';
import 'package:mi_barrio_app/core/barrio_context/emergency_mode_provider.dart';
import 'package:mi_barrio_app/core/database_sqlite/history_dao.dart';
import 'package:mi_barrio_app/core/database_sqlite/sqlite_database.dart';
import 'package:mi_barrio_app/core/database_sqlite/sqlite_tables.dart';
import 'package:mi_barrio_app/core/network/api_client.dart';
import 'package:mi_barrio_app/core/sync_manager/pending_changes.dart';
import 'package:mi_barrio_app/core/sync_manager/sync_worker.dart';
import 'package:mi_barrio_app/features/auth_barrio/data/datasources/auth_remote_datasource.dart';
import 'package:mi_barrio_app/features/auth_barrio/data/repositories/auth_repository_impl.dart';
import 'package:mi_barrio_app/features/auth_barrio/domain/entities/user_entity.dart';
import 'package:mi_barrio_app/features/emergency_support/data/datasources/support_groups_sqlite_ds.dart';
import 'package:mi_barrio_app/features/emergency_support/data/repositories/emergency_repository_impl.dart';
import 'package:mi_barrio_app/features/emergency_support/domain/entities/vulnerable_report_entity.dart';
import 'package:mi_barrio_app/features/profile_me/data/profile_local_storage.dart';
import 'package:mi_barrio_app/features/profile_me/data/profile_sync.dart';
import 'package:mi_barrio_app/features/profile_me/data/tutorial_progress.dart';
import 'package:mi_barrio_app/features/proximity_services/data/datasources/endorsements_sqlite_ds.dart';
import 'package:mi_barrio_app/features/proximity_services/data/datasources/services_remote_ds.dart';
import 'package:mi_barrio_app/features/proximity_services/data/datasources/services_sqlite_ds.dart';
import 'package:mi_barrio_app/features/proximity_services/data/models/service_model.dart';
import 'package:mi_barrio_app/features/proximity_services/presentation/widgets/offer_service_sheet.dart';
import 'package:mi_barrio_app/features/solidarity_network/data/datasources/solidarity_sqlite_ds.dart';
import 'package:mi_barrio_app/features/solidarity_network/data/models/solidarity_post_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// "Interruptor" de señal: con [online] = false toda petición falla como sin internet.
class _Net extends http.BaseClient {
  final _inner = http.Client();
  bool online = true;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (!online) throw const SocketException('Sin señal (modo avión)');
    return _inner.send(request);
  }
}

/// Un teléfono: su propia base SQLite y su propia sesión guardada.
class _Phone {
  _Phone(this.name, this.dbPath, this.base);
  final String name;
  final String dbPath;
  final String base;
  final net = _Net();
  Map<String, dynamic>? session;
  UserEntity? user;

  AuthRepositoryImpl get auth => AuthRepositoryImpl(
        remote: AuthRemoteDatasource(baseUrl: base, client: net),
        profileSync: ProfileSync(api: ApiClient(baseUrl: base, client: net)),
      );
  SyncWorker get sync => SyncWorker(baseUrl: base, client: net);
  String get tenant => user!.tenantId!;
  String get id => user!.id;

  /// "Tomar este teléfono": su base y su sesión pasan a ser las activas.
  Future<void> use() async {
    await LocalDatabase.instance.resetForTesting(path: dbPath);
    if (session != null) {
      await AuthSessionStore.instance.save(session!);
    } else {
      await AuthSessionStore.instance.clear();
    }
    EmergencyModeProvider.instance.resetForTesting();
    await EmergencyModeProvider.instance.load();
  }

  Future<void> remember() async => session = await AuthSessionStore.instance.read();
}

void main() {
  final env = Platform.environment;
  final base = env['E2E_API_URL'] ?? '';
  final joinCode = env['E2E_JOIN_CODE'] ?? '';
  final adminEmail = env['E2E_ADMIN_EMAIL'] ?? '';
  final adminPassword = env['E2E_ADMIN_PASSWORD'] ?? '';
  final skip = [base, joinCode, adminEmail, adminPassword].any((v) => v.isEmpty)
      ? 'Define E2E_API_URL, E2E_JOIN_CODE, E2E_ADMIN_EMAIL y E2E_ADMIN_PASSWORD'
      : null;

  final suffix = DateTime.now().millisecondsSinceEpoch;
  final password = 'Clave-e2e-$suffix';
  late Directory dir;
  late _Phone rosa; // vecina
  late _Phone luis; // comerciante
  late String adminToken;
  late String tenantId;

  late String serviceId; // servicio de Luis (online)
  late String favorId; // favor de Rosa (offline)
  late String sosId; // SOS de Rosa (offline)

  Future<(int, dynamic)> rest(String method, String path, {Object? body, String? token}) async {
    final req = http.Request(method, Uri.parse('$base$path'))
      ..headers['Content-Type'] = 'application/json';
    if (token != null) {
      req.headers['Authorization'] = 'Bearer $token';
      req.headers['X-Tenant-ID'] = tenantId;
    }
    if (body != null) req.body = jsonEncode(body);
    final res = await http.Response.fromStream(await req.send());
    return (res.statusCode, res.body.isEmpty ? null : jsonDecode(res.body));
  }

  Future<Database> db() => LocalDatabase.instance.database;

  setUpAll(() async {
    if (skip != null) return;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('mi_barrio_e2e');
    rosa = _Phone('Rosa', '${dir.path}${Platform.pathSeparator}rosa.db', base);
    luis = _Phone('Luis', '${dir.path}${Platform.pathSeparator}luis.db', base);
    final (s, login) = await (() async {
      final res = await http.post(Uri.parse('$base/api/v1/auth/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'email': adminEmail, 'password': adminPassword}));
      return (res.statusCode, jsonDecode(res.body));
    })();
    expect(s, 200, reason: 'login de la junta: $login');
    adminToken = login['access_token'] as String;
    tenantId = login['user']['tenant_id'] as String;
  });

  tearDownAll(() async {
    if (skip != null) return;
    await LocalDatabase.instance.close();
    await dir.delete(recursive: true);
  });

  group('Online → offline → online (servidor real)', () {
    test('1. ONLINE: Rosa y Luis se registran; el perfil local trae el rol real', () async {
      await rosa.use();
      rosa.user = await rosa.auth.register(
        fullName: 'Rosa Quispe', email: 'rosa.$suffix@e2e.test', password: password,
        role: UserRole.vecino, joinCode: joinCode);
      await rosa.remember();
      expect((await ProfileLocalStorage().getProfile(rosa.id))!.role, 'VECINO');

      await luis.use();
      luis.user = await luis.auth.register(
        fullName: 'Luis Ramos', email: 'luis.$suffix@e2e.test', password: password,
        role: UserRole.comerciante, joinCode: joinCode);
      await luis.remember();
      expect((await loadMerchantProfile(luis.id, tenantId: luis.tenant)).isMerchant, isTrue,
          reason: 'el comerciante debe ver "Ofrecer servicio"');

      // La junta aprueba al comerciante (regla nueva del Dev 1).
      final (s, b) = await rest('PATCH', '/api/v1/users/${luis.id}/approve-merchant', token: adminToken);
      expect(s, 200, reason: '$b');
    });

    test('2. ONLINE: Luis publica un servicio y Rosa lo ve tras sincronizar', () async {
      await luis.use();
      final svc = await ServicesSqliteDatasource().insertService(
        tenantId: luis.tenant, providerUserId: luis.id, category: ServiceCategory.gasfiteria,
        title: 'Gasfitero Luis', description: 'Arreglo fugas', lat: -5.1945, lng: -80.6328,
        isAvailableInEmergency: true);
      serviceId = svc.id;
      final push = await luis.sync.pushLocalChanges(luis.tenant);
      expect(push.success, isTrue, reason: push.message);

      await rosa.use();
      final pull = await rosa.sync.pullRemoteChanges(rosa.tenant);
      expect(pull.success, isTrue, reason: pull.message);
      final services = await ServicesSqliteDatasource().getServices(rosa.tenant);
      expect(services.map((s) => s.id), contains(serviceId));
    });

    test('3. OFFLINE: Rosa hace de todo sin señal y queda guardado (Pendiente)', () async {
      await rosa.use();
      rosa.net.online = false;

      final favor = await SolidaritySqliteDatasource().publishInThreeClicks(
        tenantId: rosa.tenant, authorUserId: rosa.id, modality: SolidarityModality.prestamoHerramienta,
        title: 'Necesito una escalera', lat: -5.1950, lng: -80.6330);
      favorId = favor.id;
      await EndorsementsSqliteDatasource().rateService(
        tenantId: rosa.tenant, serviceId: serviceId, endorserUserId: rosa.id,
        rating: 5, shortComment: 'Muy puntual');
      final sos = await EmergencyRepositoryImpl().createSos(
        tenantId: rosa.tenant, reporterUserId: rosa.id,
        vulnerabilityType: VulnerabilityType.atencionMedica, urgencyLevel: UrgencyLevel.critica,
        description: 'Mi mamá tiene fiebre alta', lat: -5.1951, lng: -80.6331);
      sosId = sos.id;
      await TutorialProgress().markCompleted(tenantId: rosa.tenant, userId: rosa.id);
      await ProfileLocalStorage().saveProfile(
        userId: rosa.id, tenantId: rosa.tenant, fullName: 'Rosa Quispe', phone: '+51 911 222 333',
        homeLat: -5.1950, homeLng: -80.6330);

      final push = await rosa.sync.pushLocalChanges(rosa.tenant);
      expect(push.success, isFalse, reason: 'sin señal no se envía nada');
      // 4 registros: favor, calificación, SOS y el perfil (tutorial + teléfono son la misma fila `users`).
      expect(await PendingChanges.count(rosa.tenant), 4);
      final counts = await HistoryDao().counts(rosa.tenant, rosa.id);
      expect([counts.posts, counts.sos], [1, 1]);
    });

    test('4. Mientras tanto (ONLINE): la junta activa la emergencia y crea un grupo; Luis publica otro servicio', () async {
      var (s, b) = await rest('PATCH', '/api/v1/tenants/emergency-toggle',
          body: {'is_emergency_active': true}, token: adminToken);
      expect(s, 200, reason: '$b');
      (s, b) = await rest('POST', '/api/v1/emergency/support-groups',
          body: {'name': 'Brigada E2E', 'group_type': 'PRIMEROS_AUXILIOS', 'lat': -5.1940, 'lng': -80.6325},
          token: adminToken);
      expect(s, 201, reason: '$b');

      await luis.use();
      await ServicesSqliteDatasource().insertService(
        tenantId: luis.tenant, providerUserId: luis.id, category: ServiceCategory.electricidad,
        title: 'Electricista Luis', lat: -5.1946, lng: -80.6329);
      expect((await luis.sync.pushLocalChanges(luis.tenant)).success, isTrue);
    });

    test('5. Rosa CIERRA y REABRE la app sin señal: entra y todo sigue ahí', () async {
      await rosa.use(); // reabrir = nueva conexión a su base y sesión guardada
      rosa.net.online = false;
      final restored = await rosa.auth.restoreSession();
      expect(restored?.id, rosa.id, reason: 'sin señal entra con la sesión guardada');

      expect(await PendingChanges.count(rosa.tenant), 4);
      final favor = await SolidaritySqliteDatasource().getPost(rosa.tenant, favorId);
      expect(favor!.syncStatus, SqliteTables.syncPending);
      expect(await TutorialProgress().isCompleted(rosa.id), isTrue);
      final profile = (await ProfileLocalStorage().getProfile(rosa.id))!;
      expect(profile.phone, '+51 911 222 333', reason: 'la edición offline no se pierde al reabrir');
      expect(profile.role, 'VECINO');
    });

    test('6. Rosa vuelve ONLINE: sube todo y ve lo nuevo (emergencia, grupo, servicio)', () async {
      await rosa.use();
      rosa.net.online = true;
      final result = await rosa.sync.pushLocalChanges(rosa.tenant);
      expect(result.success, isTrue, reason: result.message);
      expect(await PendingChanges.count(rosa.tenant), 0);
      final favorRow = (await (await db()).query('solidarity_posts', where: 'id = ?', whereArgs: [favorId])).single;
      expect(favorRow['sync_status'], SqliteTables.syncSynced);

      final pull = await rosa.sync.pullRemoteChanges(rosa.tenant);
      expect(pull.success, isTrue, reason: pull.message);
      expect(EmergencyModeProvider.instance.isActive.value, isTrue, reason: 'llegó la emergencia de la junta');
      final titles = (await ServicesSqliteDatasource().getServices(rosa.tenant)).map((s) => s.title);
      expect(titles, containsAll(['Gasfitero Luis', 'Electricista Luis']));
      final gasfitero = (await ServicesSqliteDatasource().getServices(rosa.tenant))
          .firstWhere((s) => s.id == serviceId);
      expect(gasfitero.ratingAvg, 5.0, reason: 'el promedio lo recalculó el servidor');
      expect((await SupportGroupsSqliteDatasource().activeGroups(rosa.tenant)).map((g) => g.name),
          contains('Brigada E2E'));

      // El servidor guardó su perfil y el tutorial.
      final (s, me) = await rest('GET', '/api/v1/users/me', token: rosa.session!['token'] as String);
      expect(s, 200);
      expect(me['phone'], '+51 911 222 333');
      expect(me['tutorial_completed'], isTrue);
    });

    test('7. Luis (online) ve lo de Rosa, coordina su favor y va en camino a su SOS', () async {
      await luis.use();
      expect((await luis.sync.pullRemoteChanges(luis.tenant)).success, isTrue);
      expect(await SolidaritySqliteDatasource().getPost(luis.tenant, favorId), isNotNull);
      final reports = await EmergencyRepositoryImpl().activeReports(luis.tenant);
      expect(reports.map((r) => r.id), contains(sosId));

      final reviews = await ServicesRemoteDatasource(api: ApiClient(baseUrl: base, client: luis.net))
          .fetchEndorsements(tenantId: luis.tenant, serviceId: serviceId);
      expect(reviews.fromServer, isTrue);
      expect(reviews.items.single.shortComment, 'Muy puntual');

      // Luis se queda sin señal y aun así coordina y ofrece ayuda.
      luis.net.online = false;
      await SolidaritySqliteDatasource().coordinatePost(
          tenantId: luis.tenant, postId: favorId, coordinatorUserId: luis.id);
      await EmergencyRepositoryImpl().offerHelp(tenantId: luis.tenant, reportId: sosId, helperUserId: luis.id);
      expect((await luis.sync.pushLocalChanges(luis.tenant)).success, isFalse);

      luis.net.online = true;
      final push = await luis.sync.pushLocalChanges(luis.tenant);
      expect(push.success, isTrue, reason: push.message);
    });

    test('8. Rosa ve que la están ayudando (favor en coordinación y vecino en camino)', () async {
      await rosa.use();
      expect((await rosa.sync.pullRemoteChanges(rosa.tenant)).success, isTrue);
      expect((await SolidaritySqliteDatasource().getPost(rosa.tenant, favorId))!.status,
          SolidarityStatus.enCoordinacion);
      final sos = (await EmergencyRepositoryImpl().activeReports(rosa.tenant)).firstWhere((r) => r.id == sosId);
      expect(sos.status, ReportStatus.vecinosEnCamino);
      expect(sos.helperUserId, luis.id);
    });

    test('9. Reinicio SIN señal en plena emergencia: la app sigue en modo emergencia', () async {
      await rosa.use(); // use() reinicia el estado y llama a load(), como al abrir la app
      rosa.net.online = false;
      expect(EmergencyModeProvider.instance.isActive.value, isTrue);
    });

    test('10. La junta desactiva la emergencia: al volver la señal, Rosa vuelve a normal', () async {
      final (s, _) = await rest('PATCH', '/api/v1/tenants/emergency-toggle',
          body: {'is_emergency_active': false}, token: adminToken);
      expect(s, 200);
      await rosa.use();
      rosa.net.online = true;
      expect((await rosa.sync.pullRemoteChanges(rosa.tenant)).success, isTrue);
      expect(EmergencyModeProvider.instance.isActive.value, isFalse);
      await rosa.use(); // y al reabrir tampoco vuelve a naranja
      expect(EmergencyModeProvider.instance.isActive.value, isFalse);
    });

    test('12. Comerciante AÚN NO aprobado: su servicio espera y sube cuando la junta lo aprueba', () async {
      final nuevo = _Phone('Ana', '${dir.path}${Platform.pathSeparator}ana.db', base);
      await nuevo.use();
      nuevo.user = await nuevo.auth.register(
        fullName: 'Ana Torres', email: 'ana.$suffix@e2e.test', password: password,
        role: UserRole.comerciante, joinCode: joinCode);
      await nuevo.remember();
      final svc = await ServicesSqliteDatasource().insertService(
        tenantId: nuevo.tenant, providerUserId: nuevo.id, category: ServiceCategory.clases,
        title: 'Clases de Ana', lat: -5.1945, lng: -80.6328);

      final waiting = await nuevo.sync.pushLocalChanges(nuevo.tenant);
      expect(waiting.waitingCount, 1, reason: 'todavía no está aprobada: queda esperando');
      expect(waiting.success, isTrue, reason: 'esperar la aprobación no es un error de sync');
      Future<Map<String, Object?>> row() async =>
          (await (await db()).query('local_services', where: 'id = ?', whereArgs: [svc.id])).single;
      expect((await row())['sync_status'], SqliteTables.syncPending, reason: 'no debe quedar "Sin enviar"');
      expect(await PendingChanges.count(nuevo.tenant), 1, reason: 'sigue en la cola para reintentar');

      final (s, b) = await rest('PATCH', '/api/v1/users/${nuevo.id}/approve-merchant', token: adminToken);
      expect(s, 200, reason: '$b');
      final sent = await nuevo.sync.pushLocalChanges(nuevo.tenant);
      expect(sent.success, isTrue, reason: sent.message);
      expect((await row())['sync_status'], SqliteTables.syncSynced);
    });

    test('13. Teléfono compartido: Rosa cierra sesión y entra Luis → ve los favores publicados y no queda basura', () async {
      await rosa.use();
      rosa.net.online = false;
      final orphan = await EmergencyRepositoryImpl().createSos(
        tenantId: rosa.tenant, reporterUserId: rosa.id,
        vulnerabilityType: VulnerabilityType.faltaSuministros, urgencyLevel: UrgencyLevel.media,
        description: 'SOS que nunca se envió', lat: -5.1951, lng: -80.6331);
      // Cerrar sesión (lo que hace AuthNotifier.logout): se borran los datos PRIVADOS de Rosa.
      await rosa.auth.purgeLocalUserData(tenantId: rosa.tenant, userId: rosa.id);
      await rosa.auth.logout();
      // El pull es incremental: lo que se borre aquí NO vuelve a bajar (salvo los
      // últimos 30 s de margen). Por eso lo ya publicado no se debe borrar.
      expect(await SolidaritySqliteDatasource().getPost(rosa.tenant, favorId), isNotNull,
          reason: 'cerrar sesión no debe borrar del teléfono lo ya PUBLICADO en el barrio');

      // Luis entra en el MISMO teléfono, con señal.
      rosa.net.online = true;
      final luisAqui = await rosa.auth.login(email: 'luis.$suffix@e2e.test', password: password);
      await rosa.auth.reconcilePendingData(luisAqui);
      expect((await rosa.sync.pullRemoteChanges(luisAqui.tenantId!)).success, isTrue);

      expect(await SolidaritySqliteDatasource().getPost(luisAqui.tenantId!, favorId), isNotNull,
          reason: 'el favor PUBLICADO de Rosa es del barrio: Luis lo debe seguir viendo');
      final reports = await EmergencyRepositoryImpl().activeReports(luisAqui.tenantId!);
      expect(reports.map((r) => r.id), isNot(contains(orphan.id)),
          reason: 'el SOS sin enviar de Rosa no debe quedar "Pendiente" para siempre');
      expect(await (await db()).query('users', where: 'id = ?', whereArgs: [rosa.id]), isEmpty,
          reason: 'el perfil de Rosa (privado) sí se borra');

      // Rosa vuelve a su teléfono para los siguientes pasos.
      await rosa.auth.logout();
      final back = await rosa.auth.login(email: 'rosa.$suffix@e2e.test', password: password);
      await rosa.auth.reconcilePendingData(back);
      await rosa.remember();
    });

    test('11. Sesión vencida sin señal: lo pendiente NO se pierde y sube al volver a entrar', () async {
      await rosa.use();
      rosa.net.online = false;
      final favor = await SolidaritySqliteDatasource().publishInThreeClicks(
        tenantId: rosa.tenant, authorUserId: rosa.id, modality: SolidarityModality.donacionMaterial,
        title: 'Dono frazadas', lat: -5.1950, lng: -80.6330);

      // Vuelve la señal pero el token ya no sirve (401).
      rosa.net.online = true;
      await AuthSessionStore.instance.save({...rosa.session!, 'token': 'token-vencido'});
      final push = await rosa.sync.pushLocalChanges(rosa.tenant);
      expect(push.unauthorized, isTrue);
      await rosa.auth.keepPendingDataFor(tenantId: rosa.tenant, userId: rosa.id); // lo hace AuthNotifier

      // La misma persona vuelve a entrar → se conserva y sube.
      final again = await rosa.auth.login(email: 'rosa.$suffix@e2e.test', password: password);
      await rosa.auth.reconcilePendingData(again);
      await rosa.remember();
      final retry = await rosa.sync.pushLocalChanges(rosa.tenant);
      expect(retry.success, isTrue, reason: retry.message);
      final row = (await (await db()).query('solidarity_posts', where: 'id = ?', whereArgs: [favor.id])).single;
      expect(row['sync_status'], SqliteTables.syncSynced);
    });
  }, skip: skip);
}
