import 'package:uuid/uuid.dart';
import '../../../../core/database_sqlite/sqlite_database.dart';
import '../../../../core/database_sqlite/sync_outbox_dao.dart';

class SolidaritySqliteDatasource {
  final SyncOutboxDao _outboxDao = SyncOutboxDao();

  Future<void> publishInThreeClicks({
    required String tenantId,
    required String authorUserId,
    required String modality, // Clic 2: Herramienta, Ayuda, etc.
    required String title,    // Clic 3: Título rápido
    required double lat,
    required double lng,
  }) async {
    final db = await LocalDatabase.instance.database;
    final String generatedId = const Uuid().v4();
    final String nowIso = DateTime.now().toUtc().toIso8601String();

    final recordMap = {
      'id': generatedId,
      'tenant_id': tenantId,
      'author_user_id': authorUserId,
      'flow_type': 'SOLICITO_AYUDA',
      'modality': modality,
      'title': title,
      'description': '',
      'is_emergency_context': 0,
      'status': 'DISPONIBLE',
      'lat': lat,
      'lng': lng,
      'is_deleted': 0,
      'updated_at': nowIso,
      'sync_status': 'PENDING',
    };

    // 1. Escritura instantánea en SQLite (la UI se actualiza en 0 ms)
    await db.insert('solidarity_posts', recordMap);

    // 2. Registro en la cola outbox para subir a PostgreSQL en cuanto haya red
    await _outboxDao.queueMutation(
      tenantId: tenantId,
      targetTable: 'solidarity_posts',
      recordId: generatedId,
      operation: 'UPSERT',
      payload: recordMap,
    );
  }
}