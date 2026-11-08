import '../../domain/entities/user_entity.dart';

class UserModel extends UserEntity {
  const UserModel({
    required super.id,
    required super.tenantId,
    required super.fullName,
    required super.role,
    required super.token,
    required super.tenantName,
    required super.joinCode,
    required super.centerLat,
    required super.centerLng,
    super.email,
    super.emailVerified,
    super.hasPassword,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    final role = UserRole.fromApi(json['role']?.toString() ?? '');
    final tenant = json['tenant'] is Map<String, dynamic>
        ? json['tenant'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final tenantId = (json['tenant_id'] ?? tenant['id'])?.toString();
    final id = json['id']?.toString();
    final token = (json['access_token'] ?? json['token'])?.toString();
    if (id == null ||
        token == null ||
        (role != UserRole.superAdmin && tenantId == null)) {
      throw const FormatException('Respuesta de autenticación incompleta');
    }

    return UserModel(
      id: id,
      tenantId: tenantId,
      fullName: json['full_name']?.toString() ?? '',
      role: role,
      token: token,
      tenantName: tenant['name']?.toString(),
      joinCode: tenant['join_code']?.toString(),
      centerLat: _doubleValue(tenant['center_lat']),
      centerLng: _doubleValue(tenant['center_lng']),
      email: json['email']?.toString(),
      emailVerified: json['email_verified'] is bool
          ? json['email_verified'] as bool
          : true,
      hasPassword: json['has_password'] is bool
          ? json['has_password'] as bool
          : true,
    );
  }

  factory UserModel.fromStoredJson(Map<String, dynamic> json) =>
      UserModel.fromJson(json);

  Map<String, dynamic> toJson() => {
    'id': id,
    'tenant_id': tenantId,
    'full_name': fullName,
    'role': role.apiValue,
    'token': token,
    'email': email,
    'email_verified': emailVerified,
    'has_password': hasPassword,
    'tenant': tenantId == null
        ? null
        : {
            'id': tenantId,
            'name': tenantName,
            'join_code': joinCode,
            'center_lat': centerLat,
            'center_lng': centerLng,
          },
  };

  static double? _doubleValue(Object? value) =>
      value is num ? value.toDouble() : null;
}
