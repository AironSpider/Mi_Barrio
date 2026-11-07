import '../../../../core/database_sqlite/local_id.dart';
import '../../../../core/database_sqlite/record_validation.dart';
import '../../../../core/database_sqlite/sqlite_database.dart';
import '../../../../core/database_sqlite/sqlite_tables.dart';
import '../../../../core/database_sqlite/sync_outbox_dao.dart';
import '../models/solidarity_post_model.dart';

/// Acceso offline al muro solidario. Funciona 100% sin internet.
class SolidaritySqliteDatasource {
  SolidaritySqliteDatasource({LocalDatabase? database, SyncOutboxDao? outboxDao})
      : _db = database ?? LocalDatabase.instance,
        _outboxDao = outboxDao ?? SyncOutboxDao();

  final LocalDatabase _db;
  final SyncOutboxDao _outboxDao;

  /// Guarda una publicación al instante (Clic 3: "Publicar Ahora").
  ///
  /// - Genera el UUID v4 en el teléfono.
  /// - Guarda la fila con `sync_status = 'PENDING'`.
  /// - Encola la mutación UPSERT en `sync_outbox`.
  /// Ambas escrituras van en una sola transacción.
  ///
  /// Lanza [ArgumentError] si algún dato es inválido (no se guarda nada).
  Future<SolidarityPostModel> publishInThreeClicks({
    required String tenantId,
    required String authorUserId,
    required String modality, // Clic 2: Herramienta, Habilidad, Material, Soporte
    required String title, // Clic 3: una línea
    required double lat,
    required double lng,
    String flowType = SolidarityFlowType.solicitoAyuda,
    String? description,
    bool isEmergencyContext = false,
  }) async {
    RecordValidation.uuid(tenantId, 'tenantId');
    RecordValidation.uuid(authorUserId, 'authorUserId');
    RecordValidation.oneOf(modality, SolidarityModality.values, 'modality');
    RecordValidation.oneOf(flowType, SolidarityFlowType.values, 'flowType');
    RecordValidation.coordinates(lat, lng);
    final cleanTitle = RecordValidation.requiredText(title, 'title',
        maxLength: SolidarityPostModel.maxTitleLength);
    final cleanDescription = description?.trim();

    final post = SolidarityPostModel(
      id: LocalId.generate(),
      tenantId: tenantId,
      authorUserId: authorUserId,
      flowType: flowType,
      modality: modality,
      title: cleanTitle,
      description:
          (cleanDescription == null || cleanDescription.isEmpty) ? null : cleanDescription,
      isEmergencyContext: isEmergencyContext,
      lat: lat,
      lng: lng,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
      syncStatus: SqliteTables.syncPending,
    );

    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.insert(SolidarityPostModel.table, post.toSqlite());
      await _outboxDao.queueMutation(
        tenantId: tenantId,
        targetTable: SolidarityPostModel.table,
        recordId: post.id,
        operation: OutboxOperation.upsert,
        payload: post.toSyncPayload(),
        executor: txn,
      );
    });
    return post;
  }

  /// Publicaciones activas del barrio, de la más reciente a la más antigua.
  Future<List<SolidarityPostModel>> getActivePosts(
    String tenantId, {
    String? modality,
    bool emergencyOnly = false,
  }) async {
    final where = StringBuffer('tenant_id = ? AND is_deleted = 0');
    final args = <Object?>[tenantId];
    if (modality != null) {
      where.write(' AND modality = ?');
      args.add(modality);
    }
    if (emergencyOnly) where.write(' AND is_emergency_context = 1');

    final db = await _db.database;
    final rows = await db.query(
      SolidarityPostModel.table,
      where: where.toString(),
      whereArgs: args,
      orderBy: 'updated_at DESC',
    );
    return rows.map(SolidarityPostModel.fromSqlite).toList();
  }

  /// Cuántas publicaciones del barrio aún no llegan al servidor.
  Future<int> countPending(String tenantId) async {
    final db = await _db.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${SolidarityPostModel.table} '
      'WHERE tenant_id = ? AND sync_status = ?',
      [tenantId, SqliteTables.syncPending],
    );
    return result.first['c'] as int;
  }
}
