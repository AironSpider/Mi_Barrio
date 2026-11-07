import '../entities/vulnerable_report_entity.dart';

/// Contrato entre la UI de emergencia (Dev 3) y los datos (Dev 2).
///
/// Dev 2 lo implementa en `data/repositories/emergency_repository_impl.dart`
/// usando SQLite (`vulnerable_reports` + `sync_outbox`), igual que el muro:
/// - [createSos] guarda al instante sin red (PENDING + outbox).
/// - [activeReports] lee del teléfono.
/// - [changes] emite cuando cambian los datos (publicación local o pull).
/// Luego se registra con `EmergencyReports.use(EmergencyRepositoryImpl())`
/// (ver `presentation/providers/emergency_provider.dart`).
abstract class EmergencyRepository {
  /// Pedidos de ayuda vigentes del barrio (no borrados).
  Future<List<VulnerableReport>> activeReports(String tenantId);

  /// Crea un SOS. Debe funcionar sin internet.
  Future<VulnerableReport> createSos({
    required String tenantId,
    required String reporterUserId,
    required String vulnerabilityType,
    required String urgencyLevel,
    required String description,
    required double lat,
    required double lng,
  });

  /// "Voy en camino": el vecino [helperUserId] se ofrece a ayudar.
  Future<VulnerableReport> offerHelp({
    required String tenantId,
    required String reportId,
    required String helperUserId,
  });

  /// Avisa a las pantallas que deben recargar.
  Stream<void> get changes;
}
