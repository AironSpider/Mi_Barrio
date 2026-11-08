import 'package:sqflite/sqflite.dart';

import '../../../../core/barrio_context/tenant_session.dart';
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

  /// Tope de la foto (JPEG comprimido en base64), igual que las calificaciones.
  static const maxPhotoB64Length = 80 * 1024;

  /// Fotos por favor (igual que los servicios).
  static const maxPhotos = 4;

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
    String? photoB64,
    List<String> photos = const [],
  }) async {
    final allPhotos = [?photoB64, ...photos];
    if (allPhotos.length > maxPhotos) {
      throw ArgumentError.value(allPhotos.length, 'photos', 'Máximo $maxPhotos fotos');
    }
    for (final photo in allPhotos) {
      if (photo.length > maxPhotoB64Length) {
        throw ArgumentError.value(
          '(${photo.length} caracteres)',
          'photoB64',
          'La foto es demasiado grande; elige otra o tómala de nuevo',
        );
      }
    }
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
      hasPhoto: allPhotos.isNotEmpty,
      photoCount: allPhotos.length,
    );

    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.insert(SolidarityPostModel.table, post.toSqlite());
      await _savePhotos(txn, tenantId, post.id, allPhotos);
      await _outboxDao.queueMutation(
        tenantId: tenantId,
        targetTable: SolidarityPostModel.table,
        recordId: post.id,
        operation: OutboxOperation.upsert,
        // Las fotos viajan solo al crear; los cambios de estado no las reenvían.
        // La primera también va en photo_b64 (servidores y apps anteriores).
        payload: {
          ...post.toSyncPayload(),
          if (allPhotos.isNotEmpty) 'photo_b64': allPhotos.first,
          if (allPhotos.isNotEmpty) 'photos': allPhotos,
        },
        executor: txn,
      );
    });
    return post;
  }

  /// Fotos del favor guardadas en el teléfono, en orden (vacío si aún no se
  /// descargaron).
  Future<List<String>> localPhotos(String postId) async {
    final db = await _db.database;
    final rows = await db.query('post_photo_list',
        columns: ['photo_b64'],
        where: 'post_id = ?',
        whereArgs: [postId],
        orderBy: 'position ASC');
    return [for (final r in rows) r['photo_b64']! as String];
  }

  /// Primera foto (compatibilidad).
  Future<String?> localPhoto(String postId) async {
    final photos = await localPhotos(postId);
    return photos.isEmpty ? null : photos.first;
  }

  /// Guarda las fotos descargadas para verlas luego sin internet.
  Future<void> cachePhotos(String tenantId, String postId, List<String> photos) async {
    final db = await _db.database;
    await db.transaction((txn) => _savePhotos(txn, tenantId, postId, photos));
  }

  /// Compatibilidad: guarda una sola foto.
  Future<void> cachePhoto(String tenantId, String postId, String photoB64) =>
      cachePhotos(tenantId, postId, [photoB64]);

  static Future<void> _savePhotos(
    DatabaseExecutor db,
    String tenantId,
    String postId,
    List<String> photos,
  ) async {
    await db.delete('post_photo_list', where: 'post_id = ?', whereArgs: [postId]);
    for (final (i, photo) in photos.indexed) {
      await db.insert('post_photo_list', {
        'post_id': postId,
        'position': i,
        'tenant_id': tenantId,
        'photo_b64': photo,
      });
    }
  }

  /// Publicaciones activas del barrio, de la más reciente a la más antigua.
  ///
  /// [includeCompleted] = false oculta los favores COMPLETADO (el muro).
  Future<List<SolidarityPostModel>> getActivePosts(
    String tenantId, {
    String? modality,
    bool emergencyOnly = false,
    bool includeCompleted = true,
    String? viewerUserId,
  }) async {
    // Lo que está en revisión por reportes solo lo ve quien lo publicó; lo que
    // este vecino reportó deja de verlo.
    final viewer = viewerUserId ?? TenantSession.instance.userId;
    final where = StringBuffer(
      'tenant_id = ? AND is_deleted = 0 '
      'AND (is_under_review = 0 OR author_user_id = ?) '
      'AND id NOT IN (SELECT target_id FROM content_reports WHERE reporter_user_id = ?)',
    );
    final args = <Object?>[tenantId, viewer, viewer];
    if (modality != null) {
      where.write(' AND modality = ?');
      args.add(modality);
    }
    if (emergencyOnly) where.write(' AND is_emergency_context = 1');
    if (!includeCompleted) {
      where.write(' AND status != ?');
      args.add(SolidarityStatus.completado);
    }

    final db = await _db.database;
    final rows = await db.query(
      SolidarityPostModel.table,
      where: where.toString(),
      whereArgs: args,
      orderBy: 'updated_at DESC',
    );
    return rows.map(SolidarityPostModel.fromSqlite).toList();
  }

  /// Un favor del barrio por id (null si no existe o fue borrado).
  Future<SolidarityPostModel?> getPost(String tenantId, String postId) async {
    final db = await _db.database;
    final rows = await db.query(
      SolidarityPostModel.table,
      where: 'id = ? AND tenant_id = ? AND is_deleted = 0',
      whereArgs: [postId, tenantId],
      limit: 1,
    );
    return rows.isEmpty ? null : SolidarityPostModel.fromSqlite(rows.first);
  }

  /// El autor cambia el estado de SU favor (DISPONIBLE / EN_COORDINACION /
  /// COMPLETADO). Funciona sin internet: queda PENDING y entra a la cola.
  ///
  /// Lanza [ArgumentError] si el favor no existe, no es suyo o el estado no
  /// es válido. Si el estado ya es ese, no encola nada.
  Future<SolidarityPostModel> changeMyPostStatus({
    required String tenantId,
    required String postId,
    required String authorUserId,
    required String newStatus,
  }) async {
    RecordValidation.oneOf(newStatus, SolidarityStatus.values, 'newStatus');
    final current = await _requirePost(tenantId, postId);
    if (current.authorUserId != authorUserId) {
      throw ArgumentError.value(
          postId, 'postId', 'Solo el autor puede cambiar el estado de su favor');
    }
    if (current.status == newStatus) return current;
    return _saveStatus(current, newStatus);
  }

  /// Otro vecino toma un favor ajeno: DISPONIBLE → EN_COORDINACION.
  ///
  /// Sin internet queda PENDING y sube al reconectar. Contrato con el backend
  /// (igual que "Voy en camino" del SOS): el payload es el favor completo con
  /// su `author_user_id` ORIGINAL y `status = EN_COORDINACION`; el servidor ve
  /// que quien envía no es el autor y solo acepta ese cambio de estado.
  ///
  /// Lanza [ArgumentError] si el favor no existe o es propio, y [StateError]
  /// si ya alguien lo coordina o está COMPLETADO.
  Future<SolidarityPostModel> coordinatePost({
    required String tenantId,
    required String postId,
    required String coordinatorUserId,
  }) async {
    final current = await _requirePost(tenantId, postId);
    if (current.authorUserId == coordinatorUserId) {
      throw ArgumentError.value(
          postId, 'postId', 'No puedes coordinar tu propio favor');
    }
    if (current.status == SolidarityStatus.enCoordinacion) {
      throw StateError('Otro vecino ya está coordinando este favor');
    }
    if (current.status == SolidarityStatus.completado) {
      throw StateError('Este favor ya fue completado');
    }
    return _saveStatus(
      current,
      SolidarityStatus.enCoordinacion,
      coordinatorUserId: coordinatorUserId,
    );
  }

  Future<SolidarityPostModel> _requirePost(String tenantId, String postId) async {
    final post = await getPost(tenantId, postId);
    if (post == null) {
      throw ArgumentError.value(postId, 'postId', 'Favor no encontrado');
    }
    return post;
  }

  /// Guarda el nuevo estado y su mutación en la cola en una sola transacción.
  /// "Disponible" otra vez = ya nadie está ayudando (igual que el servidor).
  Future<SolidarityPostModel> _saveStatus(
    SolidarityPostModel current,
    String status, {
    String? coordinatorUserId,
  }) async {
    final updated = current.copyWith(
      status: status,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
      syncStatus: SqliteTables.syncPending,
      coordinatorUserId: coordinatorUserId,
      clearCoordinator: status == SolidarityStatus.disponible,
    );
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.update(
        SolidarityPostModel.table,
        {
          'status': updated.status,
          'updated_at': updated.updatedAt,
          'sync_status': updated.syncStatus,
          'coordinator_user_id': updated.coordinatorUserId,
          'coordinator_name': updated.coordinatorName,
        },
        where: 'id = ? AND tenant_id = ?',
        whereArgs: [updated.id, updated.tenantId],
      );
      await _outboxDao.queueMutation(
        tenantId: updated.tenantId,
        targetTable: SolidarityPostModel.table,
        recordId: updated.id,
        operation: OutboxOperation.upsert,
        payload: updated.toSyncPayload(),
        executor: txn,
      );
    });
    return updated;
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
