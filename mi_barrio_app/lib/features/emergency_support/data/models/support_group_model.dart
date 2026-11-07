/// Tipos de grupo de apoyo (contrato: `support_groups.group_type`).
class SupportGroupType {
  SupportGroupType._();
  static const primerosAuxilios = 'PRIMEROS_AUXILIOS';
  static const rescate = 'RESCATE';
  static const albergue = 'ALBERGUE';
  static const alimentos = 'ALIMENTOS';
  static const logistica = 'LOGISTICA';
  static const saludMental = 'SALUD_MENTAL';

  static const labels = {
    primerosAuxilios: 'Primeros auxilios',
    rescate: 'Rescate',
    albergue: 'Albergue',
    alimentos: 'Alimentos',
    logistica: 'Logística',
    saludMental: 'Apoyo emocional',
  };

  static Set<String> get values => labels.keys.toSet();
}

/// Grupo de apoyo del barrio (brigada, albergue, olla común...).
/// Lo registra la junta en el servidor; el teléfono solo lo lee (sin internet).
class SupportGroupModel {
  const SupportGroupModel({
    required this.id,
    required this.tenantId,
    required this.name,
    required this.groupType,
    this.description,
    this.contactPhone,
    this.meetingPoint,
    this.lat,
    this.lng,
    this.coordinatorUserId,
    this.isActive = true,
    required this.updatedAt,
    this.distanceKm,
  });

  static const table = 'support_groups';

  final String id;
  final String tenantId;
  final String name;
  final String groupType;
  final String? description;
  final String? contactPhone;
  final String? meetingPoint;
  final double? lat;
  final double? lng;
  final String? coordinatorUserId;
  final bool isActive;
  final String updatedAt;

  /// Distancia al vecino; null si el grupo no tiene ubicación o no se pidió.
  final double? distanceKm;

  String get typeLabel => SupportGroupType.labels[groupType] ?? groupType;

  bool get hasPhone => contactPhone != null && contactPhone!.trim().isNotEmpty;

  SupportGroupModel withDistance(double? km) => SupportGroupModel(
        id: id,
        tenantId: tenantId,
        name: name,
        groupType: groupType,
        description: description,
        contactPhone: contactPhone,
        meetingPoint: meetingPoint,
        lat: lat,
        lng: lng,
        coordinatorUserId: coordinatorUserId,
        isActive: isActive,
        updatedAt: updatedAt,
        distanceKm: km,
      );

  factory SupportGroupModel.fromSqlite(Map<String, Object?> r) => SupportGroupModel(
        id: r['id'] as String,
        tenantId: r['tenant_id'] as String,
        name: r['name'] as String,
        groupType: r['group_type'] as String,
        description: r['description'] as String?,
        contactPhone: r['contact_phone'] as String?,
        meetingPoint: r['meeting_point'] as String?,
        lat: (r['lat'] as num?)?.toDouble(),
        lng: (r['lng'] as num?)?.toDouble(),
        coordinatorUserId: r['coordinator_user_id'] as String?,
        isActive: (r['is_active'] as int? ?? 1) == 1,
        updatedAt: r['updated_at'] as String,
      );
}
