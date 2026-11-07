import '../../../../core/database_sqlite/sqlite_tables.dart';

/// Categorías de oficios (contrato: `category`), con etiqueta para la UI.
class ServiceCategory {
  ServiceCategory._();
  static const gasfiteria = 'GASFITERIA';
  static const carpinteria = 'CARPINTERIA';
  static const electricidad = 'ELECTRICIDAD';
  static const paseadorMascotas = 'PASEADOR_MASCOTAS';
  static const clases = 'CLASES';
  static const cerrajeria = 'CERRAJERIA';
  static const soporteEmergencia = 'SOPORTE_EMERGENCIA';

  static const labels = {
    gasfiteria: 'Gasfitería',
    carpinteria: 'Carpintería',
    electricidad: 'Electricidad',
    paseadorMascotas: 'Paseador de mascotas',
    clases: 'Clases',
    cerrajeria: 'Cerrajería',
    soporteEmergencia: 'Soporte en emergencia',
  };

  static Set<String> get values => labels.keys.toSet();
}

/// Oficio del directorio vecinal (`local_services`).
class LocalServiceModel {
  const LocalServiceModel({
    required this.id,
    required this.tenantId,
    required this.providerUserId,
    required this.category,
    required this.title,
    this.description = '',
    this.isAvailableInEmergency = false,
    this.endorsementsCount = 0,
    required this.lat,
    required this.lng,
    this.isDeleted = false,
    required this.updatedAt,
    this.syncStatus = SqliteTables.syncPending,
  });

  static const table = 'local_services';
  static const maxTitleLength = 200;

  final String id;
  final String tenantId;
  final String providerUserId;
  final String category;
  final String title;
  final String description;
  final bool isAvailableInEmergency;

  /// Lo calcula el servidor a partir de `neighbor_endorsements`;
  /// el teléfono solo lo muestra.
  final int endorsementsCount;
  final double lat;
  final double lng;
  final bool isDeleted;
  final String updatedAt;
  final String syncStatus;

  bool get isPending => syncStatus == SqliteTables.syncPending;

  Map<String, Object?> toSqlite() => {
        'id': id,
        'tenant_id': tenantId,
        'provider_user_id': providerUserId,
        'category': category,
        'title': title,
        'description': description,
        'is_available_in_emergency': isAvailableInEmergency ? 1 : 0,
        'endorsements_count': endorsementsCount,
        'lat': lat,
        'lng': lng,
        'is_deleted': isDeleted ? 1 : 0,
        'updated_at': updatedAt,
        'sync_status': syncStatus,
      };

  /// Payload para `/sync/push`. No incluye `endorsements_count`: si dos
  /// teléfonos lo enviaran offline, Last-Write-Wins perdería avales.
  Map<String, Object?> toSyncPayload() => {
        'id': id,
        'provider_user_id': providerUserId,
        'category': category,
        'title': title,
        'description': description,
        'is_available_in_emergency': isAvailableInEmergency,
        'lat': lat,
        'lng': lng,
        'is_deleted': isDeleted,
        'updated_at': updatedAt,
      };

  factory LocalServiceModel.fromSqlite(Map<String, Object?> row) {
    return LocalServiceModel(
      id: row['id'] as String,
      tenantId: row['tenant_id'] as String,
      providerUserId: row['provider_user_id'] as String,
      category: row['category'] as String,
      title: row['title'] as String,
      description: row['description'] as String? ?? '',
      isAvailableInEmergency: (row['is_available_in_emergency'] as int? ?? 0) == 1,
      endorsementsCount: row['endorsements_count'] as int? ?? 0,
      lat: (row['lat'] as num).toDouble(),
      lng: (row['lng'] as num).toDouble(),
      isDeleted: (row['is_deleted'] as int? ?? 0) == 1,
      updatedAt: row['updated_at'] as String,
      syncStatus: row['sync_status'] as String? ?? SqliteTables.syncSynced,
    );
  }
}
