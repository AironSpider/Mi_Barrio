import '../../../core/database_sqlite/sqlite_tables.dart';

/// Roles del vecino (contrato: `users.role`), con etiqueta legible.
class UserRole {
  UserRole._();
  static const vecino = 'VECINO';
  static const liderVecinal = 'LIDER_VECINAL';
  static const grupoApoyo = 'GRUPO_APOYO';

  static const comerciante = 'COMERCIANTE';
  static const adminBarrio = 'ADMIN_BARRIO';

  static const labels = {
    vecino: 'Vecino',
    liderVecinal: 'Líder vecinal',
    grupoApoyo: 'Grupo de apoyo',
    comerciante: 'Comerciante',
    adminBarrio: 'Junta vecinal',
  };

  static Set<String> get values => labels.keys.toSet();
}

/// Tipo de publicador (v3, "Perfil de publicador").
class PublisherType {
  PublisherType._();
  static const labels = {
    'PERSONA_NATURAL': 'Persona natural',
    'EMPRENDEDOR': 'Emprendedor',
    'BODEGA': 'Bodega',
    'MINI_EMPRESA': 'Mini empresa',
    'EMPRESA': 'Empresa',
  };

  static Set<String> get values => labels.keys.toSet();
}

/// Perfil del vecino (tabla `users`).
class UserProfileModel {
  const UserProfileModel({
    required this.id,
    required this.tenantId,
    required this.fullName,
    this.phone = '',
    this.addressReference,
    required this.homeLat,
    required this.homeLng,
    this.role = UserRole.vecino,
    this.tutorialCompleted = false,
    this.email,
    this.emailContacto,
    this.whatsapp,
    this.facebookUrl,
    this.instagramUrl,
    this.photoB64,
    this.publisherType,
    this.publisherCategory,
    this.publisherName,
    this.isDeleted = false,
    required this.updatedAt,
    this.syncStatus = SqliteTables.syncPending,
  });

  static const table = 'users';

  final String id;
  final String tenantId;
  final String fullName;
  final String phone;
  final String? addressReference;
  final double homeLat;
  final double homeLng;
  final String role;
  final bool tutorialCompleted;
  final String? email;

  /// Correo para que los vecinos te contacten (distinto del correo de la cuenta).
  final String? emailContacto;
  final String? whatsapp;
  final String? facebookUrl;
  final String? instagramUrl;
  final String? photoB64;
  final String? publisherType;
  final String? publisherCategory;
  final String? publisherName;
  final bool isDeleted;
  final String updatedAt;
  final String syncStatus;

  bool get isPending => syncStatus == SqliteTables.syncPending;

  /// Iniciales para el avatar cuando no hay foto ("María López" → "ML").
  String get initials {
    final parts = fullName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }

  String get roleLabel => UserRole.labels[role] ?? 'Vecino';

  Map<String, Object?> toSqlite() => {
        'id': id,
        'tenant_id': tenantId,
        'full_name': fullName,
        'phone': phone,
        'address_reference': addressReference,
        'home_lat': homeLat,
        'home_lng': homeLng,
        'role': role,
        'tutorial_completed': tutorialCompleted ? 1 : 0,
        'email': email,
        'email_contacto': emailContacto,
        'whatsapp': whatsapp,
        'facebook_url': facebookUrl,
        'instagram_url': instagramUrl,
        'photo_b64': photoB64,
        'publisher_type': publisherType,
        'publisher_category': publisherCategory,
        'publisher_name': publisherName,
        'is_deleted': isDeleted ? 1 : 0,
        'updated_at': updatedAt,
        'sync_status': syncStatus,
      };

  /// Payload para `/sync/push`. El rol NO viaja: no se puede auto-asignar
  /// "Líder vecinal" desde el teléfono.
  Map<String, Object?> toSyncPayload() => {
        'id': id,
        'full_name': fullName,
        'phone': phone,
        'address_reference': addressReference,
        'home_lat': homeLat,
        'home_lng': homeLng,
        'tutorial_completed': tutorialCompleted,
        'email': email,
        'email_contacto': emailContacto,
        'whatsapp': whatsapp,
        'facebook_url': facebookUrl,
        'instagram_url': instagramUrl,
        'photo_b64': photoB64,
        'publisher_type': publisherType,
        'publisher_category': publisherCategory,
        'publisher_name': publisherName,
        'is_deleted': isDeleted,
        'updated_at': updatedAt,
      };

  factory UserProfileModel.fromSqlite(Map<String, Object?> r) => UserProfileModel(
        id: r['id'] as String,
        tenantId: r['tenant_id'] as String,
        fullName: r['full_name'] as String,
        phone: r['phone'] as String? ?? '',
        addressReference: r['address_reference'] as String?,
        homeLat: (r['home_lat'] as num).toDouble(),
        homeLng: (r['home_lng'] as num).toDouble(),
        role: r['role'] as String? ?? UserRole.vecino,
        tutorialCompleted: (r['tutorial_completed'] as int? ?? 0) == 1,
        email: r['email'] as String?,
        emailContacto: r['email_contacto'] as String?,
        whatsapp: r['whatsapp'] as String?,
        facebookUrl: r['facebook_url'] as String?,
        instagramUrl: r['instagram_url'] as String?,
        photoB64: r['photo_b64'] as String?,
        publisherType: r['publisher_type'] as String?,
        publisherCategory: r['publisher_category'] as String?,
        publisherName: r['publisher_name'] as String?,
        isDeleted: (r['is_deleted'] as int? ?? 0) == 1,
        updatedAt: r['updated_at'] as String,
        syncStatus: r['sync_status'] as String? ?? SqliteTables.syncSynced,
      );
}
