import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mi_barrio_app/core/database_sqlite/history_dao.dart';
import 'package:mi_barrio_app/core/database_sqlite/sqlite_database.dart';
import 'package:mi_barrio_app/core/database_sqlite/sqlite_tables.dart';
import 'package:mi_barrio_app/core/network/api_client.dart';
import 'package:mi_barrio_app/core/sync_manager/sync_worker.dart';
import 'package:mi_barrio_app/features/emergency_support/data/models/vulnerable_report_model.dart';
import 'package:mi_barrio_app/features/emergency_support/domain/entities/vulnerable_report_entity.dart';
import 'package:mi_barrio_app/features/proximity_services/data/datasources/endorsements_sqlite_ds.dart';
import 'package:mi_barrio_app/features/proximity_services/data/datasources/services_remote_ds.dart';
import 'package:mi_barrio_app/features/proximity_services/data/models/endorsement_model.dart';
import 'package:mi_barrio_app/features/proximity_services/data/models/service_model.dart';
import 'package:mi_barrio_app/features/solidarity_network/data/datasources/solidarity_sqlite_ds.dart';
import 'package:mi_barrio_app/features/solidarity_network/data/models/solidarity_post_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Sprint 10 · Dev 2: estados de favores, coordinar sin red, historial y calificaciones.
void main() {
  const tenant = 'a1b2c3d4-e5f6-4a8b-9c0d-1e2f3a4b5c6d';
  const otherTenant = 'b2c3d4e5-f6a7-4b8c-9d0e-2f3a4b5c6d7e';
  const me = '5f3a2c1b-1234-4abc-9def-0123456789ab';
  const neighbor = '7c6b5a49-3827-4a16-8f05-e4d3c2b1a098';
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
  final ds = SolidaritySqliteDatasource();

  /// Favor ya sincronizado (como si hubiera bajado en el pull).
  Future<String> syncedPost({
    String id = '11111111-1111-4111-8111-111111111111',
    String author = neighbor,
    String status = SolidarityStatus.disponible,
    String tenantId = tenant,
    String updatedAt = '2026-11-07T10:00:00.000Z',
    bool deleted = false,
  }) async {
    await (await db()).insert(
      SolidarityPostModel.table,
      SolidarityPostModel(
        id: id,
        tenantId: tenantId,
        authorUserId: author,
        flowType: SolidarityFlowType.solicitoAyuda,
        modality: SolidarityModality.prestamoHerramienta,
        title: 'Préstamo de camilla',
        status: status,
        lat: lat,
        lng: lng,
        isDeleted: deleted,
        updatedAt: updatedAt,
        syncStatus: SqliteTables.syncSynced,
      ).toSqlite(),
    );
    return id;
  }

  Future<List<Map<String, Object?>>> outbox() async =>
      (await db()).query('sync_outbox', orderBy: 'outbox_id ASC');

  Future<Map<String, Object?>> postRow(String id) async =>
      (await (await db()).query(SolidarityPostModel.table, where: 'id = ?', whereArgs: [id]))
          .single;

  http.Response pushOk(List<String> ids, {List<Map<String, String>> rejected = const []}) =>
      http.Response(
        jsonEncode({
          'success': true,
          'processed_count': ids.length,
          'server_timestamp': '2026-11-07T20:00:00Z',
          'processed_record_ids': ids,
          'rejected': rejected,
        }),
        200,
      );

  group('Coordinar un favor ajeno (offline-first)', () {
    test('sin red → EN_COORDINACION + PENDING → sube al reconectar → SYNCED', () async {
      final id = await syncedPost();

      // 1) Sin señal: se guarda al instante.
      final updated = await ds.coordinatePost(
        tenantId: tenant,
        postId: id,
        coordinatorUserId: me,
      );
      expect(updated.status, SolidarityStatus.enCoordinacion);
      expect(updated.isPending, isTrue);
      final row = await postRow(id);
      expect(row['status'], SolidarityStatus.enCoordinacion);
      expect(row['sync_status'], SqliteTables.syncPending);

      final queued = await outbox();
      expect(queued, hasLength(1));
      final payload = jsonDecode(queued.single['payload_json'] as String) as Map;
      expect(payload['status'], SolidarityStatus.enCoordinacion);
      // Contrato: el autor sigue siendo el original (el servidor ve que no soy yo).
      expect(payload['author_user_id'], neighbor);
      expect(payload['title'], 'Préstamo de camilla');

      // Mientras no hay señal, el push falla y nada se pierde.
      final offline = MockClient((_) async => throw const SocketException('Sin señal'));
      final failed = await SyncWorker(baseUrl: 'http://api', client: offline)
          .pushLocalChanges(tenant);
      expect(failed.success, isFalse);
      expect(await outbox(), hasLength(1));

      // 2) Vuelve la señal.
      late Map<String, dynamic> sent;
      final online = MockClient((req) async {
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        return pushOk([id]);
      });
      final result = await SyncWorker(baseUrl: 'http://api', client: online)
          .pushLocalChanges(tenant);

      expect(result.success, isTrue);
      final mutation = (sent['mutations'] as List).single as Map;
      expect(mutation['target_table'], 'solidarity_posts');
      expect((mutation['payload'] as Map)['status'], SolidarityStatus.enCoordinacion);
      expect(await outbox(), isEmpty);
      expect((await postRow(id))['sync_status'], SqliteTables.syncSynced);
    });

    test('el pull no pisa mi coordinación mientras está PENDING', () async {
      final id = await syncedPost();
      await ds.coordinatePost(tenantId: tenant, postId: id, coordinatorUserId: me);

      final client = MockClient((_) async => http.Response(
            jsonEncode({
              'server_timestamp': '2026-11-07T20:00:00Z',
              'tenant': {'id': tenant, 'is_emergency_active': false},
              'delta': {
                'solidarity_posts': [
                  {
                    'id': id,
                    'tenant_id': tenant,
                    'author_user_id': neighbor,
                    'flow_type': SolidarityFlowType.solicitoAyuda,
                    'modality': SolidarityModality.prestamoHerramienta,
                    'title': 'Préstamo de camilla',
                    'status': SolidarityStatus.disponible,
                    'lat': lat,
                    'lng': lng,
                    'is_deleted': false,
                    'updated_at': '2026-11-07T10:00:00Z',
                  },
                ],
              },
            }),
            200,
          ));
      await SyncWorker(baseUrl: 'http://api', client: client).pullRemoteChanges(tenant);

      expect((await postRow(id))['status'], SolidarityStatus.enCoordinacion);
    });

    test('si el servidor la rechaza, queda FAILED y sale de la cola', () async {
      final id = await syncedPost();
      await ds.coordinatePost(tenantId: tenant, postId: id, coordinatorUserId: me);

      final client = MockClient((_) async => pushOk(const [], rejected: [
            {
              'target_table': 'solidarity_posts',
              'record_id': id,
              'reason': 'no puedes modificar un registro de otro usuario',
            },
          ]));
      final result = await SyncWorker(baseUrl: 'http://api', client: client)
          .pushLocalChanges(tenant);

      expect(result.success, isFalse);
      expect(await outbox(), isEmpty);
      expect((await postRow(id))['sync_status'], SqliteTables.syncFailed);
    });

    test('no se puede coordinar: mi propio favor, uno ya tomado, uno completado o inexistente',
        () async {
      final mine = await syncedPost(id: '22222222-2222-4222-8222-222222222222', author: me);
      final taken = await syncedPost(
          id: '33333333-3333-4333-8333-333333333333', status: SolidarityStatus.enCoordinacion);
      final done = await syncedPost(
          id: '44444444-4444-4444-8444-444444444444', status: SolidarityStatus.completado);
      final deleted = await syncedPost(id: '55555555-5555-4555-8555-555555555555', deleted: true);
      final foreignTenant = await syncedPost(
          id: '66666666-6666-4666-8666-666666666666', tenantId: otherTenant);

      Future<void> coordinate(String id) =>
          ds.coordinatePost(tenantId: tenant, postId: id, coordinatorUserId: me);

      await expectLater(coordinate(mine), throwsArgumentError);
      await expectLater(coordinate(taken), throwsStateError);
      await expectLater(coordinate(done), throwsStateError);
      await expectLater(coordinate(deleted), throwsArgumentError);
      await expectLater(coordinate(foreignTenant), throwsArgumentError);
      await expectLater(coordinate('77777777-7777-4777-8777-777777777777'), throwsArgumentError);
      expect(await outbox(), isEmpty); // ningún intento dejó basura en la cola
    });
  });

  group('Cambiar el estado de mis favores', () {
    test('DISPONIBLE → EN_COORDINACION → COMPLETADO, cada cambio PENDING + cola', () async {
      final id = await syncedPost(author: me);

      for (final status in [SolidarityStatus.enCoordinacion, SolidarityStatus.completado]) {
        final updated = await ds.changeMyPostStatus(
          tenantId: tenant,
          postId: id,
          authorUserId: me,
          newStatus: status,
        );
        expect(updated.status, status);
        expect((await postRow(id))['status'], status);
        expect((await postRow(id))['sync_status'], SqliteTables.syncPending);
      }

      final queued = await outbox();
      expect(queued, hasLength(2));
      expect(
        queued.map((m) => (jsonDecode(m['payload_json'] as String) as Map)['status']),
        [SolidarityStatus.enCoordinacion, SolidarityStatus.completado],
      );
    });

    test('se puede reabrir un favor (COMPLETADO → DISPONIBLE)', () async {
      final id = await syncedPost(author: me, status: SolidarityStatus.completado);
      final updated = await ds.changeMyPostStatus(
          tenantId: tenant, postId: id, authorUserId: me, newStatus: SolidarityStatus.disponible);
      expect(updated.status, SolidarityStatus.disponible);
    });

    test('mismo estado → no encola nada', () async {
      final id = await syncedPost(author: me);
      await ds.changeMyPostStatus(
          tenantId: tenant, postId: id, authorUserId: me, newStatus: SolidarityStatus.disponible);
      expect(await outbox(), isEmpty);
      expect((await postRow(id))['sync_status'], SqliteTables.syncSynced);
    });

    test('otro vecino no puede cambiar mi favor; estado inválido se rechaza', () async {
      final id = await syncedPost(author: neighbor);
      await expectLater(
        ds.changeMyPostStatus(
            tenantId: tenant, postId: id, authorUserId: me, newStatus: SolidarityStatus.completado),
        throwsArgumentError,
      );
      final mine = await syncedPost(id: '22222222-2222-4222-8222-222222222222', author: me);
      await expectLater(
        ds.changeMyPostStatus(tenantId: tenant, postId: mine, authorUserId: me, newStatus: 'CERRADO'),
        throwsArgumentError,
      );
      expect(await outbox(), isEmpty);
    });

    test('el muro puede ocultar los COMPLETADO', () async {
      await syncedPost(id: '22222222-2222-4222-8222-222222222222');
      await syncedPost(
          id: '33333333-3333-4333-8333-333333333333', status: SolidarityStatus.completado);
      expect(await ds.getActivePosts(tenant), hasLength(2));
      final wall = await ds.getActivePosts(tenant, includeCompleted: false);
      expect(wall.single.id, '22222222-2222-4222-8222-222222222222');
    });
  });

  group('Mi historial (history_dao)', () {
    Future<void> service(String id, String provider,
        {String tenantId = tenant, bool deleted = false, String updatedAt = '2026-11-07T10:00:00Z'}) async {
      await (await db()).insert(
        LocalServiceModel.table,
        LocalServiceModel(
          id: id,
          tenantId: tenantId,
          providerUserId: provider,
          category: ServiceCategory.gasfiteria,
          title: 'Gasfitero $id',
          lat: lat,
          lng: lng,
          isDeleted: deleted,
          updatedAt: updatedAt,
          syncStatus: SqliteTables.syncSynced,
        ).toSqlite(),
      );
    }

    Future<void> sos(String id, String reporter, {String tenantId = tenant}) async {
      await (await db()).insert(
        VulnerableReportModel.table,
        VulnerableReportModel.toSqlite(
          VulnerableReport(
            id: id,
            tenantId: tenantId,
            reporterUserId: reporter,
            urgencyLevel: UrgencyLevel.critica,
            vulnerabilityType: VulnerabilityType.atencionMedica,
            description: 'Necesito ayuda',
            lat: lat,
            lng: lng,
            updatedAt: '2026-11-07T11:00:00Z',
          ),
          syncStatus: SqliteTables.syncSynced,
        ),
      );
    }

    test('solo lo mío, de mi barrio, sin borrados, lo más reciente primero', () async {
      await service('s-viejo', me, updatedAt: '2026-11-07T08:00:00Z');
      await service('s-nuevo', me, updatedAt: '2026-11-07T12:00:00Z');
      await service('s-ajeno', neighbor);
      await service('s-borrado', me, deleted: true);
      await service('s-otro-barrio', me, tenantId: otherTenant);

      // Favor publicado sin red: aparece con su estado PENDING.
      final pending = await ds.publishInThreeClicks(
        tenantId: tenant,
        authorUserId: me,
        modality: SolidarityModality.donacionMaterial,
        title: 'Dono frazadas',
        lat: lat,
        lng: lng,
      );
      await syncedPost(id: '22222222-2222-4222-8222-222222222222', author: neighbor);

      await sos('sos-mio', me);
      await sos('sos-ajeno', neighbor);
      await sos('sos-otro-barrio', me, tenantId: otherTenant);

      final history = HistoryDao();
      expect((await history.myServices(tenant, me)).map((s) => s.id), ['s-nuevo', 's-viejo']);
      final posts = await history.myPosts(tenant, me);
      expect(posts.single.id, pending.id);
      expect(posts.single.isPending, isTrue);
      expect((await history.mySos(tenant, me)).single.id, 'sos-mio');

      final counts = await history.counts(tenant, me);
      expect([counts.services, counts.posts, counts.sos, counts.total], [2, 1, 1, 4]);
    });

    test('vecino sin publicaciones → listas vacías y contador 0', () async {
      final history = HistoryDao();
      expect(await history.myPosts(tenant, me), isEmpty);
      expect((await history.counts(tenant, me)).total, 0);
    });
  });

  group('Calificaciones desde el servidor (services_remote_ds)', () {
    const serviceId = '88888888-8888-4888-8888-888888888888';
    const provider = '99999999-9999-4999-8999-999999999999';
    final mine = EndorsementModel.idFor(serviceId, me);
    final theirs = EndorsementModel.idFor(serviceId, neighbor);

    setUp(() async {
      await (await db()).insert(
        LocalServiceModel.table,
        const LocalServiceModel(
          id: serviceId,
          tenantId: tenant,
          providerUserId: provider,
          category: ServiceCategory.gasfiteria,
          title: 'Don Pedro',
          lat: lat,
          lng: lng,
          updatedAt: '2026-11-07T09:00:00Z',
          syncStatus: SqliteTables.syncSynced,
        ).toSqlite(),
      );
    });

    Map<String, Object?> serverRow(String id, String endorser, int rating,
            {String updatedAt = '2026-11-07T12:00:00Z', bool photo = false}) =>
        {
          'id': id,
          'service_id': serviceId,
          'endorser_user_id': endorser,
          'rating': rating,
          'short_comment': 'Muy puntual',
          'has_photo': photo,
          'updated_at': updatedAt,
        };

    ServicesRemoteDatasource remote(MockClient client) =>
        ServicesRemoteDatasource(api: ApiClient(baseUrl: 'http://api', client: client));

    test('con red: lista, promedio, fotos aparte y queda guardada para verla sin red', () async {
      final client = MockClient((req) async {
        expect(req.url.path, '/api/v1/services/$serviceId/endorsements');
        expect(req.headers['X-Tenant-ID'], tenant);
        return http.Response(
          jsonEncode([
            serverRow(theirs, neighbor, 5, photo: true),
            serverRow(mine, me, 4, updatedAt: '2026-11-07T13:00:00Z'),
          ]),
          200,
        );
      });

      final reviews = await remote(client).fetchEndorsements(tenantId: tenant, serviceId: serviceId);
      expect(reviews.fromServer, isTrue);
      expect(reviews.items.map((e) => e.id), [mine, theirs]);
      expect(reviews.average, 4.5);
      expect(reviews.withPhoto, {theirs});
      expect(reviews.items.first.photoB64, isNull); // la lista no trae fotos

      // Sin red: se ve lo que quedó guardado.
      final offline = MockClient((_) async => throw const SocketException('Sin señal'));
      final cached = await remote(offline).fetchEndorsements(tenantId: tenant, serviceId: serviceId);
      expect(cached.fromServer, isFalse);
      expect(cached.items.map((e) => e.id).toSet(), {mine, theirs});
      expect(cached.items.every((e) => e.syncStatus == SqliteTables.syncSynced), isTrue);
    });

    test('mi calificación hecha sin red no la pisa la versión vieja del servidor', () async {
      await EndorsementsSqliteDatasource().rateService(
        tenantId: tenant,
        serviceId: serviceId,
        endorserUserId: me,
        rating: 2,
        shortComment: 'Llegó tarde',
      );
      final client = MockClient((_) async => http.Response(
            jsonEncode({
              'items': [serverRow(mine, me, 5, updatedAt: '2026-11-07T08:00:00Z')],
            }),
            200,
          ));

      final reviews = await remote(client).fetchEndorsements(tenantId: tenant, serviceId: serviceId);
      expect(reviews.items.single.rating, 2);
      expect(reviews.items.single.isPending, isTrue);

      final stored = await EndorsementsSqliteDatasource().myRating(serviceId, me);
      expect(stored!.rating, 2);
      expect(stored.syncStatus, SqliteTables.syncPending);
    });

    test('endpoint aún no existe (404) → usa lo del teléfono, sin error', () async {
      final client = MockClient((_) async => http.Response('Not Found', 404));
      final reviews = await remote(client).fetchEndorsements(tenantId: tenant, serviceId: serviceId);
      expect(reviews.fromServer, isFalse);
      expect(reviews.items, isEmpty);
      expect(reviews.average, isNull);
    });

    test('ignora filas mal formadas, de otro servicio o borradas', () async {
      final client = MockClient((_) async => http.Response(
            jsonEncode([
              serverRow(theirs, neighbor, 5),
              {'id': 'sin-fecha', 'endorser_user_id': neighbor},
              {...serverRow('otro', neighbor, 3), 'service_id': 'otro-servicio'},
              {...serverRow(mine, me, 1), 'is_deleted': true},
              {...serverRow('estrellas-raras', provider, 9)},
            ]),
            200,
          ));
      final reviews = await remote(client).fetchEndorsements(tenantId: tenant, serviceId: serviceId);
      expect(reviews.items.map((e) => e.id), containsAll([theirs, 'estrellas-raras']));
      expect(reviews.items.map((e) => e.id), isNot(contains(mine)));
      expect(reviews.items.firstWhere((e) => e.id == 'estrellas-raras').rating, isNull);
      expect(reviews.items, hasLength(2));
    });

    test('formato real del backend de Dev 1 (sin has_photo, con created_at)', () async {
      // Copia de la respuesta de GET /services/{id}/endorsements (deb060b).
      final client = MockClient((_) async => http.Response(
            jsonEncode([
              {
                'id': theirs,
                'service_id': serviceId,
                'endorser_user_id': neighbor,
                'rating': 5,
                'short_comment': 'Muy puntual',
                'created_at': '2026-11-07T21:55:01.123456+00:00',
                'updated_at': '2026-11-07T21:55:01.123456+00:00',
              },
              {
                'id': mine,
                'service_id': serviceId,
                'endorser_user_id': me,
                'rating': null,
                'short_comment': null,
                'created_at': '2026-11-07T21:50:00+00:00',
                'updated_at': '2026-11-07T21:50:00+00:00',
              },
            ]),
            200,
          ));
      final reviews = await remote(client).fetchEndorsements(tenantId: tenant, serviceId: serviceId);
      expect(reviews.items.map((e) => e.id), [theirs, mine]);
      expect(reviews.average, 5.0); // sin estrellas no cuenta
      expect(reviews.photoFlagsKnown, isFalse); // la pantalla pide la foto al abrir
      expect(reviews.withPhoto, isEmpty);
    });

    test('una calificación borrada en el servidor desaparece también sin red', () async {
      var serverRows = [serverRow(theirs, neighbor, 5), serverRow(mine, me, 4)];
      final client = MockClient((_) async => http.Response(jsonEncode(serverRows), 200));
      final ds = remote(client);
      expect((await ds.fetchEndorsements(tenantId: tenant, serviceId: serviceId)).items, hasLength(2));

      serverRows = [serverRow(mine, me, 4)]; // el vecino borró su calificación
      final online = await ds.fetchEndorsements(tenantId: tenant, serviceId: serviceId);
      expect(online.items.map((e) => e.id), [mine]);

      final offline = MockClient((_) async => throw const SocketException('Sin señal'));
      final cached = await remote(offline).fetchEndorsements(tenantId: tenant, serviceId: serviceId);
      expect(cached.items.map((e) => e.id), [mine]);
    });

    test('borrar en el servidor no oculta mi calificación pendiente de subir', () async {
      await EndorsementsSqliteDatasource().rateService(
        tenantId: tenant, serviceId: serviceId, endorserUserId: me, rating: 3);
      final client = MockClient((_) async => http.Response('[]', 200));
      final reviews = await remote(client).fetchEndorsements(tenantId: tenant, serviceId: serviceId);
      expect(reviews.items.single.id, mine);
      expect((await EndorsementsSqliteDatasource().myRating(serviceId, me))!.isPending, isTrue);
    });

    test('foto: se pide aparte; sin foto o sin red → null', () async {
      final client = MockClient((req) async {
        if (req.url.path == '/api/v1/endorsements/$theirs/photo') {
          return http.Response(jsonEncode({'photo_b64': 'aGVsbG8='}), 200);
        }
        return http.Response('Not Found', 404);
      });
      final ds = remote(client);
      expect(await ds.fetchEndorsementPhoto(tenantId: tenant, endorsementId: theirs), 'aGVsbG8=');
      expect(await ds.fetchEndorsementPhoto(tenantId: tenant, endorsementId: mine), isNull);

      final offline = MockClient((_) async => throw const SocketException('Sin señal'));
      expect(
        await remote(offline).fetchEndorsementPhoto(tenantId: tenant, endorsementId: theirs),
        isNull,
      );
    });
  });
}
