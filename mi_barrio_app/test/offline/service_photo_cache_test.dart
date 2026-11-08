import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mi_barrio_app/core/database_sqlite/local_id.dart';
import 'package:mi_barrio_app/core/database_sqlite/sqlite_database.dart';
import 'package:mi_barrio_app/core/sync_manager/sync_worker.dart';
import 'package:mi_barrio_app/features/proximity_services/data/datasources/services_sqlite_ds.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Si el comerciante cambia las fotos, el teléfono no se queda con las viejas.
void main() {
  final local = LocalDatabase.instance;
  final tenant = LocalId.generate();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
  });
  setUp(() => local.resetForTesting(path: inMemoryDatabasePath));
  tearDown(() => local.close());

  Future<void> pull(String updatedAt) async {
    final client = MockClient((_) async => http.Response(
          jsonEncode({
            'server_timestamp': '2026-11-08T20:00:00Z',
            'delta': {
              'local_services': [
                {
                  'id': 'svc-1', 'tenant_id': tenant, 'provider_user_id': 'p-1',
                  'category': 'GASFITERIA', 'title': 'Don Pedro', 'description': '',
                  'is_available_in_emergency': false, 'lat': -5.19, 'lng': -80.63,
                  'is_deleted': false, 'photo_count': 2,
                  'updated_at': updatedAt, 'server_updated_at': updatedAt,
                },
              ],
            },
          }),
          200,
        ));
    final result = await SyncWorker(baseUrl: 'http://api', client: client).pullRemoteChanges(tenant);
    expect(result.success, isTrue);
  }

  test('las fotos guardadas se borran solo cuando el servicio cambió en el servidor', () async {
    final ds = ServicesSqliteDatasource();
    await pull('2026-11-08T10:00:00Z');
    await ds.cachePhotos(tenant, 'svc-1', ['foto-a', 'foto-b']);

    await pull('2026-11-08T10:00:00Z');
    expect(await ds.localPhotos('svc-1'), ['foto-a', 'foto-b'], reason: 'misma versión: se conservan');

    await pull('2026-11-08T12:00:00Z');
    expect(await ds.localPhotos('svc-1'), isEmpty, reason: 'otra versión: se vuelven a pedir');
  });
}
