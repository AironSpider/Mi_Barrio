import '../../../../core/database_sqlite/local_id.dart';
import '../../../../core/database_sqlite/record_validation.dart';
import '../../../../core/database_sqlite/sqlite_database.dart';
import '../../../../core/database_sqlite/sqlite_tables.dart';
import '../../../../core/database_sqlite/sync_outbox_dao.dart';
import '../models/service_model.dart';

/// Acceso offline al directorio de oficios. Funciona 100% sin internet.
class ServicesSqliteDatasource {
  ServicesSqliteDatasource({LocalDatabase? database, SyncOutboxDao? outboxDao})
      : _db = database ?? LocalDatabase.instance,
        _outboxDao = outboxDao ?? SyncOutboxDao();

  final LocalDatabase _db;
  final SyncOutboxDao _outboxDao;

  /// Registra un oficio al instante con `sync_status = 'PENDING'` y lo encola
  /// para sincronizar, en una sola transacción.
  ///
  /// Lanza [ArgumentError] si algún dato es inválido (no se guarda nada).
  Future<LocalServiceModel> insertService({
    required String tenantId,
    required String providerUserId,
    required String category,
    required String title,
    required double lat,
    required double lng,
    String description = '',
    bool isAvailableInEmergency = false,
  }) async {
    RecordValidation.uuid(tenantId, 'tenantId');
    RecordValidation.uuid(providerUserId, 'providerUserId');
    RecordValidation.oneOf(category, ServiceCategory.values, 'category');
    RecordValidation.coordinates(lat, lng);
    final cleanTitle = RecordValidation.requiredText(title, 'title',
        maxLength: LocalServiceModel.maxTitleLength);

    final service = LocalServiceModel(
      id: LocalId.generate(),
      tenantId: tenantId,
      providerUserId: providerUserId,
      category: category,
      title: cleanTitle,
      description: description.trim(),
      isAvailableInEmergency: isAvailableInEmergency,
      lat: lat,
      lng: lng,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
      syncStatus: SqliteTables.syncPending,
    );

    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.insert(LocalServiceModel.table, service.toSqlite());
      await _outboxDao.queueMutation(
        tenantId: tenantId,
        targetTable: LocalServiceModel.table,
        recordId: service.id,
        operation: OutboxOperation.upsert,
        payload: service.toSyncPayload(),
        executor: txn,
      );
    });
    return service;
  }

  /// Oficios del barrio ordenados por "Visto Bueno Vecinal" (más avalados primero).
  Future<List<LocalServiceModel>> getServices(
    String tenantId, {
    String? category,
    bool emergencyOnly = false,
  }) async {
    final where = StringBuffer('tenant_id = ? AND is_deleted = 0');
    final args = <Object?>[tenantId];
    if (category != null) {
      where.write(' AND category = ?');
      args.add(category);
    }
    if (emergencyOnly) where.write(' AND is_available_in_emergency = 1');

    final db = await _db.database;
    final rows = await db.query(
      LocalServiceModel.table,
      where: where.toString(),
      whereArgs: args,
      orderBy: 'endorsements_count DESC, title ASC',
    );
    return rows.map(LocalServiceModel.fromSqlite).toList();
  }
}
