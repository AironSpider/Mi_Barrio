import '../../../../core/database_sqlite/sqlite_tables.dart';

/// Tipos de flujo (contrato: `flow_type`).
class SolidarityFlowType {
  SolidarityFlowType._();
  static const solicitoAyuda = 'SOLICITO_AYUDA';
  static const ofrezcoAyuda = 'OFREZCO_AYUDA';
  static const values = {solicitoAyuda, ofrezcoAyuda};
}

/// Modalidades (contrato: `modality`), con etiqueta en español para la UI.
class SolidarityModality {
  SolidarityModality._();
  static const prestamoHerramienta = 'PRESTAMO_HERRAMIENTA';
  static const ayudaTemporal = 'AYUDA_TEMPORAL';
  static const donacionMaterial = 'DONACION_MATERIAL';
  static const intercambioHabilidad = 'INTERCAMBIO_HABILIDAD';
  static const movilidadSolidaria = 'MOVILIDAD_SOLIDARIA';
  static const recursoCritico = 'RECURSO_CRITICO';

  static const labels = {
    prestamoHerramienta: 'Herramienta',
    intercambioHabilidad: 'Habilidad',
    donacionMaterial: 'Material',
    ayudaTemporal: 'Soporte',
    movilidadSolidaria: 'Movilidad',
    recursoCritico: 'Recurso crítico',
  };

  static Set<String> get values => labels.keys.toSet();
}

/// Estados de una publicación (contrato: `status`).
class SolidarityStatus {
  SolidarityStatus._();
  static const disponible = 'DISPONIBLE';
  static const enCoordinacion = 'EN_COORDINACION';
  static const completado = 'COMPLETADO';
  static const values = {disponible, enCoordinacion, completado};
}

/// Publicación del muro solidario. Convierte entre:
/// - SQLite (booleanos 0/1 + `sync_status`) y
/// - el payload de `/sync/push` (booleanos true/false, sin campos locales).
class SolidarityPostModel {
  const SolidarityPostModel({
    required this.id,
    required this.tenantId,
    required this.authorUserId,
    required this.flowType,
    required this.modality,
    required this.title,
    this.description,
    this.isEmergencyContext = false,
    this.status = SolidarityStatus.disponible,
    required this.lat,
    required this.lng,
    this.isDeleted = false,
    required this.updatedAt,
    this.syncStatus = SqliteTables.syncPending,
  });

  static const table = 'solidarity_posts';
  static const maxTitleLength = 200;

  final String id;
  final String tenantId;
  final String authorUserId;
  final String flowType;
  final String modality;
  final String title;
  final String? description;
  final bool isEmergencyContext;
  final String status;
  final double lat;
  final double lng;
  final bool isDeleted;

  /// ISO-8601 UTC.
  final String updatedAt;
  final String syncStatus;

  bool get isPending => syncStatus == SqliteTables.syncPending;

  Map<String, Object?> toSqlite() => {
        'id': id,
        'tenant_id': tenantId,
        'author_user_id': authorUserId,
        'flow_type': flowType,
        'modality': modality,
        'title': title,
        'description': description,
        'is_emergency_context': isEmergencyContext ? 1 : 0,
        'status': status,
        'lat': lat,
        'lng': lng,
        'is_deleted': isDeleted ? 1 : 0,
        'updated_at': updatedAt,
        'sync_status': syncStatus,
      };

  /// Payload para la cola outbox / `/sync/push` (formato del contrato).
  /// `tenant_id` viaja en el header `X-Tenant-ID`, no en el cuerpo.
  Map<String, Object?> toSyncPayload() => {
        'id': id,
        'author_user_id': authorUserId,
        'flow_type': flowType,
        'modality': modality,
        'title': title,
        'description': description,
        'is_emergency_context': isEmergencyContext,
        'status': status,
        'lat': lat,
        'lng': lng,
        'is_deleted': isDeleted,
        'updated_at': updatedAt,
      };

  factory SolidarityPostModel.fromSqlite(Map<String, Object?> row) {
    return SolidarityPostModel(
      id: row['id'] as String,
      tenantId: row['tenant_id'] as String,
      authorUserId: row['author_user_id'] as String,
      flowType: row['flow_type'] as String,
      modality: row['modality'] as String,
      title: row['title'] as String,
      description: row['description'] as String?,
      isEmergencyContext: (row['is_emergency_context'] as int? ?? 0) == 1,
      status: row['status'] as String? ?? SolidarityStatus.disponible,
      lat: (row['lat'] as num).toDouble(),
      lng: (row['lng'] as num).toDouble(),
      isDeleted: (row['is_deleted'] as int? ?? 0) == 1,
      updatedAt: row['updated_at'] as String,
      syncStatus: row['sync_status'] as String? ?? SqliteTables.syncSynced,
    );
  }
}
