import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mi_barrio_app/core/database_sqlite/sqlite_database.dart';
import 'package:mi_barrio_app/core/sync_manager/sync_worker.dart';
import 'package:mi_barrio_app/features/solidarity_network/data/datasources/solidarity_sqlite_ds.dart';
import 'package:mi_barrio_app/features/solidarity_network/data/models/solidarity_post_model.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../flutter_test_config.dart';

const _other = 'bbbbbbbb-2222-4222-8222-222222222222';

void main() {
  final local = LocalDatabase.instance;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() => local.resetForTesting(path: inMemoryDatabasePath));
  tearDown(() => local.close());

  Future<List<Map<String, Object?>>> outbox() async => (await local.database).query('sync_outbox');

  test('publicar con foto: queda en el teléfono y viaja una sola vez en el push', () async {
    final ds = SolidaritySqliteDatasource();
    final post = await ds.publishInThreeClicks(
      tenantId: testTenantId,
      authorUserId: testUserId,
      modality: SolidarityModality.prestamoHerramienta,
      title: 'Presto escalera',
      lat: -5.19,
      lng: -80.63,
      photoB64: 'AAAA',
    );
    expect(post.hasPhoto, isTrue);
    expect(await ds.localPhoto(post.id), 'AAAA');
    final payload = jsonDecode((await outbox()).single['payload_json'] as String) as Map;
    expect(payload['photo_b64'], 'AAAA');

    // Cambiar el estado no reenvía la foto.
    await ds.changeMyPostStatus(
      tenantId: testTenantId,
      postId: post.id,
      authorUserId: testUserId,
      newStatus: SolidarityStatus.completado,
    );
    final second = jsonDecode((await outbox()).last['payload_json'] as String) as Map;
    expect(second.containsKey('photo_b64'), isFalse);
  });

  test('una foto demasiado grande se rechaza antes de guardar', () async {
    expect(
      () => SolidaritySqliteDatasource().publishInThreeClicks(
        tenantId: testTenantId,
        authorUserId: testUserId,
        modality: SolidarityModality.prestamoHerramienta,
        title: 'x',
        lat: 0,
        lng: 0,
        photoB64: 'A' * (SolidaritySqliteDatasource.maxPhotoB64Length + 1),
      ),
      throwsArgumentError,
    );
    expect(await outbox(), isEmpty);
  });

  test('pull: autor, contacto, foto y quién ayuda; la foto guardada no se pierde', () async {
    final ds = SolidaritySqliteDatasource();
    await ds.cachePhoto(testTenantId, 'p1', 'FOTO');
    final client = MockClient((_) async => http.Response(jsonEncode({
          'server_timestamp': '2026-11-08T10:00:00+00:00',
          'has_more': false,
          'delta': {
            'solidarity_posts': [
              {
                'id': 'p1',
                'tenant_id': testTenantId,
                'author_user_id': _other,
                'flow_type': 'SOLICITO_AYUDA',
                'modality': 'PRESTAMO_HERRAMIENTA',
                'title': 'Necesito taladro',
                'is_emergency_context': false,
                'status': 'EN_COORDINACION',
                'lat': -5.19,
                'lng': -80.63,
                'is_deleted': false,
                'updated_at': '2026-11-08T09:00:00+00:00',
                'has_photo': true,
                'author_name': 'Rosa C.',
                'contact_phone': '987654321',
                'contact_whatsapp': null,
                'coordinator_user_id': testUserId,
                'coordinator_name': 'Yo T.',
              },
            ],
          },
        }), 200));
    final result = await SyncWorker(baseUrl: 'http://api', client: client).pullRemoteChanges(testTenantId);
    expect(result.success, isTrue);

    final post = (await ds.getPost(testTenantId, 'p1'))!;
    expect(post.authorName, 'Rosa C.');
    expect(post.contactPhone, '987654321');
    expect(post.hasPhoto, isTrue);
    expect(post.coordinatorUserId, testUserId);
    expect(await ds.localPhoto('p1'), 'FOTO', reason: 'el pull reemplaza la fila, no la foto');
  });

  test('coordinar registra quién ayuda; volver a disponible lo limpia', () async {
    final ds = SolidaritySqliteDatasource();
    final mine = await ds.publishInThreeClicks(
      tenantId: testTenantId,
      authorUserId: _other,
      modality: SolidarityModality.ayudaTemporal,
      title: 'Ayuda',
      lat: 0,
      lng: 0,
    );
    final coordinated = await ds.coordinatePost(
      tenantId: testTenantId,
      postId: mine.id,
      coordinatorUserId: testUserId,
    );
    expect(coordinated.coordinatorUserId, testUserId);
    expect((await ds.getPost(testTenantId, mine.id))!.coordinatorUserId, testUserId);

    final reopened = await ds.changeMyPostStatus(
      tenantId: testTenantId,
      postId: mine.id,
      authorUserId: _other,
      newStatus: SolidarityStatus.disponible,
    );
    expect(reopened.coordinatorUserId, isNull);
    expect((await ds.getPost(testTenantId, mine.id))!.coordinatorUserId, isNull);
  });
}
