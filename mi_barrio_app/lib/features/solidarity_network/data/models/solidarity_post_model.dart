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
    this.authorName,
    this.contactPhone,
    this.contactWhatsapp,
    this.hasPhoto = false,
    this.coordinatorUserId,
    this.coordinatorName,
    this.isUnderReview = false,
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

  // ── Solo bajada (los manda el servidor en el pull; no viajan en el push) ──
  /// Nombre público del autor ("Rosa C.").
  final String? authorName;

  /// Teléfono / WhatsApp que el autor cargó en su perfil (para coordinar).
  final String? contactPhone;
  final String? contactWhatsapp;

  /// true si tiene foto (se descarga aparte, ver `post_photos`).
  final bool hasPhoto;

  /// Quién está ayudando (lo registra el servidor al coordinar).
  final String? coordinatorUserId;
  final String? coordinatorName;

  /// 3 vecinos lo reportaron: oculto hasta que el administrador lo revise.
  final bool isUnderReview;

  bool get isPending => syncStatus == SqliteTables.syncPending;

  bool get hasPhone => contactPhone?.trim().isNotEmpty ?? false;
  bool get hasWhatsapp => contactWhatsapp?.trim().isNotEmpty ?? false;

  SolidarityPostModel copyWith({
    String? status,
    String? updatedAt,
    String? syncStatus,
    bool? hasPhoto,
    String? coordinatorUserId,
    bool clearCoordinator = false,
  }) =>
      SolidarityPostModel(
        id: id,
        tenantId: tenantId,
        authorUserId: authorUserId,
        flowType: flowType,
        modality: modality,
        title: title,
        description: description,
        isEmergencyContext: isEmergencyContext,
        status: status ?? this.status,
        lat: lat,
        lng: lng,
        isDeleted: isDeleted,
        updatedAt: updatedAt ?? this.updatedAt,
        syncStatus: syncStatus ?? this.syncStatus,
        authorName: authorName,
        contactPhone: contactPhone,
        contactWhatsapp: contactWhatsapp,
        hasPhoto: hasPhoto ?? this.hasPhoto,
        coordinatorUserId:
            clearCoordinator ? null : coordinatorUserId ?? this.coordinatorUserId,
        coordinatorName: clearCoordinator ? null : coordinatorName,
        isUnderReview: isUnderReview,
      );

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
        'author_name': authorName,
        'contact_phone': contactPhone,
        'contact_whatsapp': contactWhatsapp,
        'has_photo': hasPhoto ? 1 : 0,
        'coordinator_user_id': coordinatorUserId,
        'coordinator_name': coordinatorName,
        'is_under_review': isUnderReview ? 1 : 0,
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
      authorName: row['author_name'] as String?,
      contactPhone: row['contact_phone'] as String?,
      contactWhatsapp: row['contact_whatsapp'] as String?,
      hasPhoto: (row['has_photo'] as int? ?? 0) == 1,
      coordinatorUserId: row['coordinator_user_id'] as String?,
      coordinatorName: row['coordinator_name'] as String?,
      isUnderReview: (row['is_under_review'] as int? ?? 0) == 1,
    );
  }
}
