import 'package:sqflite/sqflite.dart';

import '../../../../core/database_sqlite/record_validation.dart';
import '../../../../core/database_sqlite/sqlite_database.dart';
import '../../../../core/database_sqlite/sqlite_tables.dart';
import '../../../../core/database_sqlite/sync_outbox_dao.dart';
import '../models/endorsement_model.dart';
import '../models/service_model.dart';

/// Calificaciones con estrellas, 100% offline.
class EndorsementsSqliteDatasource {
  EndorsementsSqliteDatasource({
    LocalDatabase? database,
    SyncOutboxDao? outboxDao,
  }) : _db = database ?? LocalDatabase.instance,
       _outboxDao = outboxDao ?? SyncOutboxDao();

  final LocalDatabase _db;
  final SyncOutboxDao _outboxDao;

  /// Crea o edita la calificación del vecino para un servicio (upsert).
  ///
  /// - [rating] 1 a 5, o null para dejar las estrellas vacías.
  /// - [shortComment] opcional, máximo 140 caracteres.
  /// - [photoB64] opcional (JPEG comprimido).
  /// Lanza [ArgumentError] si los datos son inválidos, si el servicio no existe
  /// en el barrio o si el vecino intenta calificar su propio servicio.
  Future<EndorsementModel> rateService({
    required String tenantId,
    required String serviceId,
    required String endorserUserId,
    int? rating,
    String? shortComment,
    String? photoB64,
  }) async {
    RecordValidation.uuid(tenantId, 'tenantId');
    RecordValidation.uuid(serviceId, 'serviceId');
    RecordValidation.uuid(endorserUserId, 'endorserUserId');
    if (rating != null && (rating < 1 || rating > 5)) {
      throw ArgumentError.value(rating, 'rating', 'Debe estar entre 1 y 5');
    }
    final comment = shortComment?.trim();
    if (comment != null && comment.length > EndorsementModel.maxCommentLength) {
      throw ArgumentError.value(
        shortComment,
        'shortComment',
        'Máximo ${EndorsementModel.maxCommentLength} caracteres',
      );
    }
    if (photoB64 != null &&
        photoB64.length > EndorsementModel.maxPhotoB64Length) {
      throw ArgumentError.value(
        '(${photoB64.length} caracteres)',
        'photoB64',
        'La foto es demasiado grande; comprímela antes de guardar',
      );
    }

    final db = await _db.database;
    final service = await db.query(
      LocalServiceModel.table,
      columns: ['provider_user_id'],
      where: 'id = ? AND tenant_id = ? AND is_deleted = 0',
      whereArgs: [serviceId, tenantId],
      limit: 1,
    );
    if (service.isEmpty) {
      throw ArgumentError.value(
        serviceId,
        'serviceId',
        'Servicio no encontrado en este barrio',
      );
    }
    if (service.first['provider_user_id'] == endorserUserId) {
      throw ArgumentError.value(
        endorserUserId,
        'endorserUserId',
        'No puedes calificar tu propio servicio',
      );
    }

    final endorsement = EndorsementModel(
      id: EndorsementModel.idFor(serviceId, endorserUserId),
      tenantId: tenantId,
      serviceId: serviceId,
      endorserUserId: endorserUserId,
      rating: rating,
      shortComment: (comment == null || comment.isEmpty) ? null : comment,
      photoB64: photoB64,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
      syncStatus: SqliteTables.syncPending,
    );

    await db.transaction((txn) async {
      await txn.rawInsert(
        'INSERT OR REPLACE INTO ${EndorsementModel.table} '
        '(id, tenant_id, service_id, endorser_user_id, rating, short_comment, '
        'photo_b64, is_deleted, updated_at, sync_status) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          endorsement.id,
          endorsement.tenantId,
          endorsement.serviceId,
          endorsement.endorserUserId,
          endorsement.rating,
          endorsement.shortComment,
          endorsement.photoB64,
          0,
          endorsement.updatedAt,
          endorsement.syncStatus,
        ],
      );
      await _outboxDao.queueMutation(
        tenantId: tenantId,
        targetTable: EndorsementModel.table,
        recordId: endorsement.id,
        operation: OutboxOperation.upsert,
        payload: endorsement.toSyncPayload(),
        executor: txn,
      );
    });
    return endorsement;
  }

  /// Retira el visto bueno localmente y encola la eliminación lógica para
  /// sincronizarla con el servidor.
  Future<EndorsementModel> removeEndorsement({
    required String tenantId,
    required String serviceId,
    required String endorserUserId,
  }) async {
    RecordValidation.uuid(tenantId, 'tenantId');
    RecordValidation.uuid(serviceId, 'serviceId');
    RecordValidation.uuid(endorserUserId, 'endorserUserId');

    final existing = await myRating(serviceId, endorserUserId);
    if (existing == null || existing.tenantId != tenantId) {
      throw ArgumentError.value(
        serviceId,
        'serviceId',
        'No hay un visto bueno activo para retirar',
      );
    }

    final endorsement = EndorsementModel(
      id: existing.id,
      tenantId: tenantId,
      serviceId: serviceId,
      endorserUserId: endorserUserId,
      rating: existing.rating,
      shortComment: existing.shortComment,
      photoB64: existing.photoB64,
      isDeleted: true,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
      syncStatus: SqliteTables.syncPending,
    );
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.insert(
        EndorsementModel.table,
        endorsement.toSqlite(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await _outboxDao.queueMutation(
        tenantId: tenantId,
        targetTable: EndorsementModel.table,
        recordId: endorsement.id,
        operation: OutboxOperation.upsert,
        payload: endorsement.toSyncPayload(),
        executor: txn,
      );
    });
    return endorsement;
  }

  /// La calificación de este vecino para el servicio (null si aún no calificó).
  Future<EndorsementModel?> myRating(
    String serviceId,
    String endorserUserId,
  ) async {
    final db = await _db.database;
    final rows = await db.query(
      EndorsementModel.table,
      where: 'id = ? AND is_deleted = 0',
      whereArgs: [EndorsementModel.idFor(serviceId, endorserUserId)],
      limit: 1,
    );
    return rows.isEmpty ? null : EndorsementModel.fromSqlite(rows.first);
  }

  /// Calificaciones del servicio guardadas en el teléfono, las más recientes primero.
  Future<List<EndorsementModel>> listForService(
    String tenantId,
    String serviceId,
  ) async {
    final db = await _db.database;
    final rows = await db.query(
      EndorsementModel.table,
      where: 'tenant_id = ? AND service_id = ? AND is_deleted = 0',
      whereArgs: [tenantId, serviceId],
      orderBy: 'updated_at DESC',
    );
    return rows.map(EndorsementModel.fromSqlite).toList();
  }
}
