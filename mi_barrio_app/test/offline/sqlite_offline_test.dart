import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mi_barrio_app/core/database_sqlite/local_id.dart';
import 'package:mi_barrio_app/core/database_sqlite/sqlite_database.dart';
import 'package:mi_barrio_app/core/database_sqlite/sqlite_tables.dart';
import 'package:mi_barrio_app/core/database_sqlite/sync_outbox_dao.dart';
import 'package:mi_barrio_app/features/proximity_services/data/datasources/services_sqlite_ds.dart';
import 'package:mi_barrio_app/features/proximity_services/data/models/service_model.dart';
import 'package:mi_barrio_app/features/solidarity_network/data/datasources/solidarity_sqlite_ds.dart';
import 'package:mi_barrio_app/features/solidarity_network/data/models/solidarity_post_model.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Outbox que falla, para comprobar que la transacción no deja datos a medias.
class _FailingOutboxDao extends SyncOutboxDao {
  @override
  Future<void> queueMutation({
    required String tenantId,
    required String targetTable,
    required String recordId,
    required String operation,
    required Map<String, dynamic> payload,
    DatabaseExecutor? executor,
  }) async {
    throw StateError('falla simulada (app cerrada a la mitad)');
  }
}

void main() {
  // Barrio y vecino de prueba (UUIDs fijos).
  const tenantA = 'a1b2c3d4-e5f6-4a8b-9c0d-1e2f3a4b5c6d';
  const tenantB = 'b2c3d4e5-f6a7-4b8c-9d0e-2f3a4b5c6d7e';
  const vecino = '5f3a2c1b-1234-4abc-9def-0123456789ab';
  const lat = -12.0464; // Lima
  const lng = -77.0428;

  final local = LocalDatabase.instance;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() => local.resetForTesting(path: inMemoryDatabasePath));
  tearDown(() => local.close());

  Future<List<Map<String, Object?>>> outbox() async =>
      (await local.database).query('sync_outbox', orderBy: 'outbox_id');

  group('UUID v4 local (sin red)', () {
    test('genera 5000 ids v4 válidos y únicos', () {
      final ids = List.generate(5000, (_) => LocalId.generate());
      expect(ids.every(LocalId.isValidV4), isTrue);
      expect(ids.toSet().length, ids.length);
    });

    test('rechaza formatos inválidos', () {
      for (final bad in [
        '',
        'abc',
        '7b8f9a2e-4b71-1d3e-908a-2c8b5e9f1a3d', // versión 1, no 4
        '7b8f9a2e-4b71-4d3e-708a-2c8b5e9f1a3d', // variante incorrecta
        "1' OR '1'='1",
      ]) {
        expect(LocalId.isValidV4(bad), isFalse, reason: bad);
      }
    });
  });

  group('Esquema SQLite', () {
    test('crea todas las tablas e índices en versión ${SqliteTables.schemaVersion}',
        () async {
      final db = await local.database;
      final names = (await db.rawQuery(
              "SELECT name FROM sqlite_master WHERE type IN ('table','index')"))
          .map((r) => r['name'])
          .toSet();
      for (final t in [
        'solidarity_posts',
        'local_services',
        'sync_outbox',
        'sync_state',
        'idx_solidarity_tenant',
        'idx_services_tenant',
        'idx_outbox_tenant',
      ]) {
        expect(names, contains(t));
      }
      expect(await db.getVersion(), SqliteTables.schemaVersion);
    });

    test('pedir la base en paralelo devuelve la misma conexión', () async {
      final both = await Future.wait([local.database, local.database]);
      expect(identical(both[0], both[1]), isTrue);
    });

    test('actualiza un teléfono con la versión 1 sin perder datos pendientes',
        () async {
      final dir = await Directory.systemTemp.createTemp('mi_barrio_test');
      addTearDown(() async {
        await local.close(); // Windows no borra archivos abiertos.
        await dir.delete(recursive: true);
      });
      final path = '${dir.path}${Platform.pathSeparator}v1.db';

      // Base tal como la creaba el Sprint 1 (versión 1).
      final v1 = await databaseFactoryFfi.openDatabase(path,
          options: OpenDatabaseOptions(
            version: 1,
            onCreate: (db, _) async {
              await db.execute(SqliteTables.createSolidarityPosts);
              await db.execute(SqliteTables.createSyncOutbox);
              await db.execute(SqliteTables.createSyncState);
            },
          ));
      await v1.insert('solidarity_posts', {
        'id': LocalId.generate(),
        'tenant_id': tenantA,
        'author_user_id': vecino,
        'flow_type': 'SOLICITO_AYUDA',
        'modality': 'PRESTAMO_HERRAMIENTA',
        'title': 'Escalera',
        'lat': lat,
        'lng': lng,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
        'sync_status': 'PENDING',
      });
      await v1.close();

      await local.resetForTesting(path: path);
      final db = await local.database;
      expect(await db.getVersion(), SqliteTables.schemaVersion);
      expect((await db.query('solidarity_posts')).length, 1);
      expect(await db.query('local_services'), isEmpty); // tabla nueva creada
    });
  });

  group('Publicar en 3 clics (solidarity_posts)', () {
    test('guarda PENDING y encola la mutación con el formato del contrato',
        () async {
      final ds = SolidaritySqliteDatasource();
      final post = await ds.publishInThreeClicks(
        tenantId: tenantA,
        authorUserId: vecino,
        modality: SolidarityModality.prestamoHerramienta,
        title: '  Préstamo de escalera  ',
        lat: lat,
        lng: lng,
      );

      expect(LocalId.isValidV4(post.id), isTrue);
      expect(post.title, 'Préstamo de escalera');

      final rows = await (await local.database)
          .query('solidarity_posts', where: 'id = ?', whereArgs: [post.id]);
      expect(rows.single['sync_status'], 'PENDING');
      expect(rows.single['is_emergency_context'], 0); // INTEGER en SQLite

      final queued = await outbox();
      expect(queued.single['operation'], 'UPSERT');
      expect(queued.single['record_id'], post.id);
      expect(queued.single['tenant_id'], tenantA);

      final payload =
          jsonDecode(queued.single['payload_json'] as String) as Map<String, dynamic>;
      expect(payload['is_emergency_context'], isFalse); // booleano JSON real
      expect(payload['is_deleted'], isFalse);
      expect(payload.containsKey('sync_status'), isFalse);
      expect(payload.containsKey('tenant_id'), isFalse); // va en el header
      expect(DateTime.parse(payload['updated_at'] as String).isUtc, isTrue);
    });

    test('rechaza datos inválidos sin guardar nada', () async {
      final ds = SolidaritySqliteDatasource();
      Future<void> publish({
        String tenant = tenantA,
        String modality = SolidarityModality.donacionMaterial,
        String title = 'Calaminas',
        double latitude = lat,
        String flow = SolidarityFlowType.ofrezcoAyuda,
      }) =>
          ds.publishInThreeClicks(
            tenantId: tenant,
            authorUserId: vecino,
            modality: modality,
            title: title,
            lat: latitude,
            lng: lng,
            flowType: flow,
          );

      await expectLater(publish(title: '   '), throwsArgumentError);
      await expectLater(publish(title: 'x' * 201), throwsArgumentError);
      await expectLater(publish(modality: 'DINERO'), throwsArgumentError);
      await expectLater(publish(flow: 'VENDO'), throwsArgumentError);
      await expectLater(publish(tenant: "1' OR '1'='1"), throwsArgumentError);
      await expectLater(publish(latitude: 200), throwsArgumentError);

      expect(await ds.getActivePosts(tenantA), isEmpty);
      expect(await outbox(), isEmpty);
    });

    test('si falla la cola, la publicación tampoco se guarda (atómico)',
        () async {
      final ds = SolidaritySqliteDatasource(outboxDao: _FailingOutboxDao());
      await expectLater(
        ds.publishInThreeClicks(
          tenantId: tenantA,
          authorUserId: vecino,
          modality: SolidarityModality.ayudaTemporal,
          title: 'Ayuda con mudanza',
          lat: lat,
          lng: lng,
        ),
        throwsStateError,
      );
      expect(await SolidaritySqliteDatasource().getActivePosts(tenantA), isEmpty);
    });

    test('cada barrio solo ve sus publicaciones (multi-tenant)', () async {
      final ds = SolidaritySqliteDatasource();
      for (final t in [tenantA, tenantA, tenantB]) {
        await ds.publishInThreeClicks(
          tenantId: t,
          authorUserId: vecino,
          modality: SolidarityModality.intercambioHabilidad,
          title: 'Clases de guitarra',
          lat: lat,
          lng: lng,
        );
      }
      expect((await ds.getActivePosts(tenantA)).length, 2);
      expect((await ds.getActivePosts(tenantB)).length, 1);
      expect(await ds.countPending(tenantA), 2);
    });
  });

  group('Directorio de oficios (local_services)', () {
    test('guarda PENDING, encola sin endorsements_count y ordena por avales',
        () async {
      final ds = ServicesSqliteDatasource();
      final gasfitero = await ds.insertService(
        tenantId: tenantA,
        providerUserId: vecino,
        category: ServiceCategory.gasfiteria,
        title: 'Gasfitero Don Luis',
        lat: lat,
        lng: lng,
      );
      final electricista = await ds.insertService(
        tenantId: tenantA,
        providerUserId: vecino,
        category: ServiceCategory.electricidad,
        title: 'Electricista Rosa',
        lat: lat,
        lng: lng,
        isAvailableInEmergency: true,
      );

      // El servidor calcula los avales; simulamos que llegaron por el pull.
      await (await local.database).update('local_services',
          {'endorsements_count': 12}, where: 'id = ?', whereArgs: [electricista.id]);

      final list = await ds.getServices(tenantA);
      expect(list.map((s) => s.id), [electricista.id, gasfitero.id]);
      expect(list.first.isPending, isTrue);
      expect((await ds.getServices(tenantA, emergencyOnly: true)).single.id,
          electricista.id);

      final payload = jsonDecode((await outbox()).first['payload_json'] as String)
          as Map<String, dynamic>;
      expect(payload.containsKey('endorsements_count'), isFalse);
      expect(payload['is_available_in_emergency'], isFalse);

      await expectLater(
        ds.insertService(
          tenantId: tenantA,
          providerUserId: vecino,
          category: 'HACKER',
          title: 'x',
          lat: lat,
          lng: lng,
        ),
        throwsArgumentError,
      );
    });
  });
}
