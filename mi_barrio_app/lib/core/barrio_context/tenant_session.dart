/// Sesión del barrio (tenant) y del vecino que inició sesión.
///
/// Todos los valores vienen del servidor al iniciar sesión
/// ([applyAuthenticatedUser]); la app no trae barrios ni usuarios fijos.
/// Sin sesión los campos quedan vacíos ([hasNeighborhood] = false).
class TenantSession {
  TenantSession._();
  static final TenantSession instance = TenantSession._();

  String tenantId = '';
  String userId = '';
  String tenantName = '';
  double centerLat = 0;
  double centerLng = 0;

  /// Rol de API actual: VECINO, COMERCIANTE, ADMIN_BARRIO o SUPER_ADMIN.
  String role = 'VECINO';
  String? inviteCode;

  /// true si hay un vecino con barrio en sesión.
  bool get hasNeighborhood => tenantId.isNotEmpty;

  bool get isComerciante => role == 'COMERCIANTE';

  void applyAuthenticatedUser({
    required String authenticatedTenantId,
    required String authenticatedUserId,
    required String authenticatedTenantName,
    required String authenticatedRole,
    String? authenticatedInviteCode,
    required double authenticatedCenterLat,
    required double authenticatedCenterLng,
  }) {
    tenantId = authenticatedTenantId;
    userId = authenticatedUserId;
    tenantName = authenticatedTenantName;
    role = authenticatedRole;
    inviteCode = authenticatedInviteCode;
    centerLat = authenticatedCenterLat;
    centerLng = authenticatedCenterLng;
  }

  /// El superadministrador no pertenece a ningún barrio.
  void applyPlatformAdmin(String authenticatedUserId) {
    clearAuthenticatedUser();
    userId = authenticatedUserId;
    role = 'SUPER_ADMIN';
  }

  void clearAuthenticatedUser() {
    tenantId = '';
    userId = '';
    tenantName = '';
    role = 'VECINO';
    inviteCode = null;
    centerLat = 0;
    centerLng = 0;
  }
}
