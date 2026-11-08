import 'package:uuid/uuid.dart';

import '../../../../core/database_sqlite/sqlite_tables.dart';

/// Calificación con estrellas de un servicio (`neighbor_endorsements`).
class EndorsementModel {
  const EndorsementModel({
    required this.id,
    required this.tenantId,
    required this.serviceId,
    required this.endorserUserId,
    this.rating,
    this.shortComment,
    this.photoB64,
    this.isDeleted = false,
    required this.updatedAt,
    this.syncStatus = SqliteTables.syncPending,
    this.endorserName,
  });

  static const table = 'neighbor_endorsements';
  static const maxCommentLength = 140;

  /// Foto JPEG comprimida (~480 px) en base64: tope de seguridad ~80 KB.
  static const maxPhotoB64Length = 80 * 1024;

  /// Espacio de nombres fijo de Mi Barrio para UUID v5.
  static const _namespace = '6f1c2a3b-8d4e-4f5a-9b6c-7d8e9f0a1b2c';

  /// Id determinístico: la misma persona calificando el mismo servicio
  /// genera SIEMPRE el mismo id, en cualquier teléfono. Así el upsert
  /// funciona y el UNIQUE(service_id, endorser_user_id) del backend
  /// nunca rompe el lote de sincronización.
  static String idFor(String serviceId, String endorserUserId) =>
      const Uuid().v5(_namespace, '$serviceId:$endorserUserId');

  final String id;
  final String tenantId;
  final String serviceId;
  final String endorserUserId;

  /// 1 a 5, o null si el vecino dejó las estrellas vacías.
  final int? rating;
  final String? shortComment;
  final String? photoB64;
  final bool isDeleted;
  final String updatedAt;
  final String syncStatus;

  /// Nombre público de quien calificó ("Rosa C."); lo manda el servidor.
  final String? endorserName;

  bool get isPending => syncStatus == SqliteTables.syncPending;

  Map<String, Object?> toSqlite() => {
    'id': id,
    'tenant_id': tenantId,
    'service_id': serviceId,
    'endorser_user_id': endorserUserId,
    'rating': rating,
    'short_comment': shortComment,
    'photo_b64': photoB64,
    'is_deleted': isDeleted ? 1 : 0,
    'updated_at': updatedAt,
    'sync_status': syncStatus,
    'endorser_name': endorserName,
  };

  Map<String, Object?> toSyncPayload() => {
    'id': id,
    'service_id': serviceId,
    'endorser_user_id': endorserUserId,
    'rating': rating,
    'short_comment': shortComment,
    'photo_b64': photoB64,
    'is_deleted': isDeleted,
    'updated_at': updatedAt,
  };

  factory EndorsementModel.fromSqlite(Map<String, Object?> row) =>
      EndorsementModel(
        id: row['id'] as String,
        tenantId: row['tenant_id'] as String,
        serviceId: row['service_id'] as String,
        endorserUserId: row['endorser_user_id'] as String,
        rating: row['rating'] as int?,
        shortComment: row['short_comment'] as String?,
        photoB64: row['photo_b64'] as String?,
        isDeleted: (row['is_deleted'] as int? ?? 0) == 1,
        updatedAt: row['updated_at'] as String,
        syncStatus: row['sync_status'] as String? ?? SqliteTables.syncSynced,
        endorserName: row['endorser_name'] as String?,
      );
}
