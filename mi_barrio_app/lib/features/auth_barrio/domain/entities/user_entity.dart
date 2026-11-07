enum UserRole {
  vecino('VECINO', 'Vecino'),
  comerciante('COMERCIANTE', 'Comerciante'),
  adminBarrio('ADMIN_BARRIO', 'Administrador del barrio'),
  superAdmin('SUPER_ADMIN', 'Superadministrador');

  const UserRole(this.apiValue, this.label);

  final String apiValue;
  final String label;

  bool get isSelfSelectable =>
      this == UserRole.vecino || this == UserRole.comerciante;

  static UserRole fromApi(String value) => switch (value.toUpperCase()) {
    'VECINO' => UserRole.vecino,
    'COMERCIANTE' => UserRole.comerciante,
    'ADMIN_BARRIO' => UserRole.adminBarrio,
    'SUPER_ADMIN' => UserRole.superAdmin,
    _ => throw FormatException('Rol de usuario no soportado: $value'),
  };
}

class UserEntity {
  const UserEntity({
    required this.id,
    this.tenantId,
    required this.fullName,
    required this.role,
    required this.token,
    this.tenantName,
    this.joinCode,
    this.centerLat,
    this.centerLng,
  });

  final String id;
  final String? tenantId;
  final String fullName;
  final UserRole role;
  final String token;
  final String? tenantName;
  final String? joinCode;
  final double? centerLat;
  final double? centerLng;
}

class NeighborhoodProvisionEntity {
  const NeighborhoodProvisionEntity({
    required this.neighborhoodName,
    required this.joinCode,
    required this.adminFullName,
    required this.adminEmail,
  });

  final String neighborhoodName;
  final String joinCode;
  final String adminFullName;
  final String adminEmail;
}
