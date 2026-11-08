import 'package:sqflite/sqflite.dart';

import '../../../../core/barrio_context/tenant_session.dart';
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
    String? publisherType,
    String? publisherName,
    String? priceText,
    List<String> photos = const [],
    String flowType = LocalServiceModel.flowOffer,
  }) async {
    RecordValidation.uuid(tenantId, 'tenantId');
    RecordValidation.oneOf(
      flowType,
      const {LocalServiceModel.flowOffer, LocalServiceModel.flowNeed},
      'flowType',
    );
    RecordValidation.uuid(providerUserId, 'providerUserId');
    RecordValidation.oneOf(category, ServiceCategory.values, 'category');
    RecordValidation.coordinates(lat, lng);
    final cleanTitle = RecordValidation.requiredText(
      title,
      'title',
      maxLength: LocalServiceModel.maxTitleLength,
    );
    _checkPhotos(photos);

    final service = LocalServiceModel(
      id: LocalId.generate(),
      tenantId: tenantId,
      providerUserId: providerUserId,
      category: category,
      title: cleanTitle,
      description: description.trim(),
      isAvailableInEmergency: isAvailableInEmergency,
      publisherType: publisherType?.trim().isEmpty ?? true
          ? null
          : publisherType!.trim(),
      publisherName: publisherName?.trim().isEmpty ?? true
          ? null
          : publisherName!.trim(),
      priceText: _clean(priceText),
      photoCount: photos.length,
      flowType: flowType,
      lat: lat,
      lng: lng,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
      syncStatus: SqliteTables.syncPending,
    );

    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.insert(LocalServiceModel.table, service.toSqlite());
      await _savePhotos(txn, tenantId, service.id, photos);
      await _outboxDao.queueMutation(
        tenantId: tenantId,
        targetTable: LocalServiceModel.table,
        recordId: service.id,
        operation: OutboxOperation.upsert,
        payload: {
          ...service.toSyncPayload(),
          if (photos.isNotEmpty) 'photos': photos,
        },
        executor: txn,
      );
    });
    return service;
  }

  /// Edita un servicio PROPIO ya publicado. Funciona sin internet (PENDING).
  /// [photos] null = no se tocan las fotos; una lista = reemplaza las fotos.
  Future<LocalServiceModel> updateService({
    required LocalServiceModel current,
    required String providerUserId,
    required String category,
    required String title,
    required String description,
    required double lat,
    required double lng,
    required bool isAvailableInEmergency,
    String? priceText,
    List<String>? photos,
    String? flowType,
  }) async {
    if (current.providerUserId != providerUserId) {
      throw ArgumentError.value(
        current.id,
        'serviceId',
        'Solo puedes editar tus propios servicios',
      );
    }
    RecordValidation.oneOf(category, ServiceCategory.values, 'category');
    RecordValidation.coordinates(lat, lng);
    final cleanTitle = RecordValidation.requiredText(
      title,
      'title',
      maxLength: LocalServiceModel.maxTitleLength,
    );
    if (photos != null) _checkPhotos(photos);

    final updated = LocalServiceModel(
      id: current.id,
      tenantId: current.tenantId,
      providerUserId: current.providerUserId,
      category: category,
      title: cleanTitle,
      description: description.trim(),
      isAvailableInEmergency: isAvailableInEmergency,
      endorsementsCount: current.endorsementsCount,
      ratingAvg: current.ratingAvg,
      publisherType: current.publisherType,
      publisherName: current.publisherName,
      contactPhone: current.contactPhone,
      contactWhatsapp: current.contactWhatsapp,
      priceText: _clean(priceText),
      photoCount: photos?.length ?? current.photoCount,
      flowType: flowType ?? current.flowType,
      isUnderReview: current.isUnderReview,
      providerRole: current.providerRole,
      lat: lat,
      lng: lng,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
      syncStatus: SqliteTables.syncPending,
    );
    await _saveEdit(updated, photos: photos);
    return updated;
  }

  /// "Retirar servicio": deja de verse en el barrio (borrado lógico, se sincroniza).
  Future<void> retireService(
    LocalServiceModel current,
    String providerUserId,
  ) async {
    if (current.providerUserId != providerUserId) {
      throw ArgumentError.value(
        current.id,
        'serviceId',
        'Solo puedes retirar tus propios servicios',
      );
    }
    final retired = LocalServiceModel.fromSqlite({
      ...current.toSqlite(),
      'is_deleted': 1,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'sync_status': SqliteTables.syncPending,
    });
    await _saveEdit(retired);
  }

  Future<void> _saveEdit(
    LocalServiceModel service, {
    List<String>? photos,
  }) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.insert(
        LocalServiceModel.table,
        service.toSqlite(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      if (photos != null) {
        await _savePhotos(txn, service.tenantId, service.id, photos);
      }
      await _outboxDao.queueMutation(
        tenantId: service.tenantId,
        targetTable: LocalServiceModel.table,
        recordId: service.id,
        operation: OutboxOperation.upsert,
        payload: {...service.toSyncPayload(), 'photos': ?photos},
        executor: txn,
      );
    });
  }

  /// Fotos guardadas en el teléfono (vacío si aún no se descargaron).
  Future<List<String>> localPhotos(String serviceId) async {
    final db = await _db.database;
    final rows = await db.query(
      'service_photos',
      columns: ['photo_b64'],
      where: 'service_id = ?',
      whereArgs: [serviceId],
      orderBy: 'position ASC',
    );
    return [for (final r in rows) r['photo_b64'] as String];
  }

  /// Guarda las fotos descargadas para verlas luego sin internet.
  Future<void> cachePhotos(
    String tenantId,
    String serviceId,
    List<String> photos,
  ) async {
    final db = await _db.database;
    await db.transaction(
      (txn) => _savePhotos(txn, tenantId, serviceId, photos),
    );
  }

  static Future<void> _savePhotos(
    DatabaseExecutor db,
    String tenantId,
    String serviceId,
    List<String> photos,
  ) async {
    await db.delete(
      'service_photos',
      where: 'service_id = ?',
      whereArgs: [serviceId],
    );
    for (final (i, photo) in photos.indexed) {
      await db.insert('service_photos', {
        'service_id': serviceId,
        'position': i,
        'tenant_id': tenantId,
        'photo_b64': photo,
      });
    }
  }

  /// Tope por foto (JPEG comprimido en base64), menor que el del servidor.
  static const maxPhotoB64Length = 100 * 1024;

  static void _checkPhotos(List<String> photos) {
    if (photos.length > LocalServiceModel.maxPhotos) {
      throw ArgumentError.value(
        photos.length,
        'photos',
        'Máximo ${LocalServiceModel.maxPhotos} fotos',
      );
    }
    if (photos.any((p) => p.isEmpty || p.length > maxPhotoB64Length)) {
      throw ArgumentError.value(
        '(foto)',
        'photos',
        'Una foto es demasiado grande; elige otra',
      );
    }
  }

  static String? _clean(String? v) =>
      v == null || v.trim().isEmpty ? null : v.trim();

  /// Oficios locales del barrio, ordenados por cantidad de recomendaciones.
  Future<List<LocalServiceModel>> getServices(
    String tenantId, {
    String? category,
    bool emergencyOnly = false,
    String? viewerUserId,
  }) async {
    // Lo que está en revisión por reportes solo lo ve quien lo publicó; lo que
    // este vecino reportó deja de verlo.
    final viewer = viewerUserId ?? TenantSession.instance.userId;
    final where = StringBuffer(
      'tenant_id = ? AND is_deleted = 0 '
      'AND (is_under_review = 0 OR provider_user_id = ?) '
      'AND id NOT IN (SELECT target_id FROM content_reports WHERE reporter_user_id = ?)',
    );
    final args = <Object?>[tenantId, viewer, viewer];
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
      orderBy: 'endorsements_count DESC, COALESCE(rating_avg, 0) DESC, title COLLATE NOCASE ASC, id ASC',
    );
    return rows.map(LocalServiceModel.fromSqlite).toList();
  }
}
