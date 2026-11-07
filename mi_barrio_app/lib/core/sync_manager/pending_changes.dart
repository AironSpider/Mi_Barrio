import '../database_sqlite/sync_outbox_dao.dart';

/// Cambios hechos sin internet que todavía no llegaron al servidor.
///
/// Para el aviso de "Cerrar sesión" (pantalla Tú):
/// ```dart
/// final n = await PendingChanges.count(user.tenantId);
/// final aviso = PendingChanges.logoutWarning(n);
/// if (aviso != null) { /* mostrar diálogo de confirmación */ }
/// ```
class PendingChanges {
  PendingChanges._();

  /// Registros pendientes del barrio. Sin barrio (null) → 0.
  static Future<int> count(String? tenantId, {SyncOutboxDao? dao}) async {
    if (tenantId == null || tenantId.isEmpty) return 0;
    return (dao ?? SyncOutboxDao()).countPending(tenantId);
  }

  /// Texto del aviso al cerrar sesión, o null si no hay nada pendiente.
  static String? logoutWarning(int count) {
    if (count <= 0) return null;
    final cambios = count == 1 ? '1 cambio' : '$count cambios';
    return 'Tienes $cambios sin sincronizar. Si cierras sesión se perderán.';
  }
}
