import 'dart:async';

import 'package:mi_barrio_app/core/barrio_context/tenant_session.dart';

/// Sesión de prueba para TODOS los tests (la app ya no trae un barrio demo):
/// un vecino con barrio, como si hubiera iniciado sesión.
const testTenantId = 'a1b2c3d4-e5f6-4a8b-9c0d-1e2f3a4b5c6d';
const testUserId = '5f3a2c1b-1234-4abc-9def-0123456789ab';

void applyTestSession() => TenantSession.instance.applyAuthenticatedUser(
      authenticatedTenantId: testTenantId,
      authenticatedUserId: testUserId,
      authenticatedTenantName: 'Junta Vecinal de Prueba (Piura)',
      authenticatedRole: 'VECINO',
      authenticatedCenterLat: -5.1945,
      authenticatedCenterLng: -80.6328,
    );

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  applyTestSession();
  await testMain();
}
