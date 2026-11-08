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
  // Rubros nuevos (Sprint 13)
  static const albanileria = 'ALBANILERIA';
  static const pintura = 'PINTURA';
  static const mecanica = 'MECANICA';
  static const tecnologia = 'TECNOLOGIA';
  static const costura = 'COSTURA';
  static const belleza = 'BELLEZA';
  static const limpieza = 'LIMPIEZA';
  static const lavanderia = 'LAVANDERIA';
  static const jardineria = 'JARDINERIA';
  static const mudanza = 'MUDANZA';
  static const comida = 'COMIDA';
  static const bodega = 'BODEGA';
  static const cuidado = 'CUIDADO';
  static const salud = 'SALUD';
  static const otros = 'OTROS';

  /// En el orden en que se muestran (los más pedidos primero; "Otros" al final).
  static const labels = {
    gasfiteria: 'Gasfitería',
    electricidad: 'Electricidad',
    carpinteria: 'Carpintería',
    albanileria: 'Albañilería',
    pintura: 'Pintura',
    cerrajeria: 'Cerrajería',
    mecanica: 'Mecánica',
    tecnologia: 'Celulares y computadoras',
    costura: 'Costura',
    belleza: 'Peluquería y belleza',
    limpieza: 'Limpieza',
    lavanderia: 'Lavandería',
    jardineria: 'Jardinería',
    mudanza: 'Mudanzas y fletes',
    comida: 'Comida casera',
    bodega: 'Bodega',
    clases: 'Clases',
    cuidado: 'Cuidado de niños y mayores',
    salud: 'Salud',
    paseadorMascotas: 'Paseador de mascotas',
    soporteEmergencia: 'Soporte en emergencia',
    otros: 'Otros',
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
    this.ratingAvg,
    this.publisherType,
    this.publisherName,
    this.contactPhone,
    this.contactWhatsapp,
    this.priceText,
    this.photoCount = 0,
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

  /// Promedio de estrellas (1 a 5) calculado por el servidor; null = sin calificaciones.
  final double? ratingAvg;

  /// Perfil de publicador (v3): Persona natural, Emprendedor, Bodega, etc.
  final String? publisherType;
  final String? publisherName;

  /// Contacto del comerciante (teléfono / WhatsApp). Lo manda el servidor en
  /// el pull; el teléfono no lo envía (no viaja en [toSyncPayload]).
  final String? contactPhone;
  final String? contactWhatsapp;

  /// Precio en texto libre ("S/ 30 la visita", "A tratar"); null = sin precio.
  final String? priceText;

  /// Cuántas fotos tiene (se descargan aparte, ver `service_photos`).
  final int photoCount;

  /// Hasta 4 fotos por servicio (mismo tope que el servidor).
  static const maxPhotos = 4;

  bool get hasContact =>
      (contactPhone?.trim().isNotEmpty ?? false) ||
      (contactWhatsapp?.trim().isNotEmpty ?? false);
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
    'rating_avg': ratingAvg,
    'publisher_type': publisherType,
    'publisher_name': publisherName,
    'contact_phone': contactPhone,
    'contact_whatsapp': contactWhatsapp,
    'price_text': priceText,
    'photo_count': photoCount,
    'lat': lat,
    'lng': lng,
    'is_deleted': isDeleted ? 1 : 0,
    'updated_at': updatedAt,
    'sync_status': syncStatus,
  };

  /// Payload para `/sync/push`. No incluye `endorsements_count` ni `rating_avg`:
  /// los calcula el servidor (si dos teléfonos los enviaran, LWW perdería votos).
  Map<String, Object?> toSyncPayload() => {
    'id': id,
    'provider_user_id': providerUserId,
    'category': category,
    'title': title,
    'description': description,
    'is_available_in_emergency': isAvailableInEmergency,
    'publisher_type': publisherType,
    'publisher_name': publisherName,
    'price_text': priceText,
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
      isAvailableInEmergency:
          (row['is_available_in_emergency'] as int? ?? 0) == 1,
      endorsementsCount: row['endorsements_count'] as int? ?? 0,
      ratingAvg: (row['rating_avg'] as num?)?.toDouble(),
      publisherType: row['publisher_type'] as String?,
      publisherName: row['publisher_name'] as String?,
      contactPhone: row['contact_phone'] as String?,
      contactWhatsapp: row['contact_whatsapp'] as String?,
      priceText: row['price_text'] as String?,
      photoCount: row['photo_count'] as int? ?? 0,
      lat: (row['lat'] as num).toDouble(),
      lng: (row['lng'] as num).toDouble(),
      isDeleted: (row['is_deleted'] as int? ?? 0) == 1,
      updatedAt: row['updated_at'] as String,
      syncStatus: row['sync_status'] as String? ?? SqliteTables.syncSynced,
    );
  }
}
