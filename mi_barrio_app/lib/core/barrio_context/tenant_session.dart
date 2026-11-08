/// Sesión del barrio (tenant) y del vecino actual.
///
/// Sprint 5: barrio de demostración fijo (mismo que usa el modal de publicación).
/// Sprint 9: se reemplaza por la sesión real (código de junta vecinal + registro).
class TenantSession {
  TenantSession._();
  static final TenantSession instance = TenantSession._();

  static const demoTenantId = 'a1b2c3d4-e5f6-4a8b-9c0d-1e2f3a4b5c6d';
  static const demoUserId = '5f3a2c1b-1234-4abc-9def-0123456789ab';
  static const demoTenantName = 'Junta Vecinal Demo (Piura)';
  static const demoCenterLat = -5.1945;
  static const demoCenterLng = -80.6328;

  String tenantId = demoTenantId;
  String userId = demoUserId;
  String tenantName = demoTenantName;
  double centerLat = demoCenterLat;
  double centerLng = demoCenterLng;

  /// Rol de API actual: VECINO, COMERCIANTE, ADMIN_BARRIO o SUPER_ADMIN.
  String role = 'VECINO';
  String? inviteCode;
  bool isApproved = true;

  bool get isComerciante => role == 'COMERCIANTE';

  void applyAuthenticatedUser({
    required String authenticatedTenantId,
    required String authenticatedUserId,
    required String authenticatedTenantName,
    required String authenticatedRole,
    String? authenticatedInviteCode,
    bool authenticatedIsApproved = true,
    required double authenticatedCenterLat,
    required double authenticatedCenterLng,
  }) {
    tenantId = authenticatedTenantId;
    userId = authenticatedUserId;
    tenantName = authenticatedTenantName;
    role = authenticatedRole;
    inviteCode = authenticatedInviteCode;
    isApproved = authenticatedIsApproved;
    centerLat = authenticatedCenterLat;
    centerLng = authenticatedCenterLng;
  }

  void applyPlatformAdmin(String authenticatedUserId) {
    clearAuthenticatedUser();
    userId = authenticatedUserId;
    tenantName = '';
    role = 'SUPER_ADMIN';
  }

  void clearAuthenticatedUser() {
    tenantId = demoTenantId;
    userId = demoUserId;
    tenantName = demoTenantName;
    role = 'VECINO';
    inviteCode = null;
    isApproved = true;
    centerLat = demoCenterLat;
    centerLng = demoCenterLng;
  }
}
