import 'dart:async';

import '../../../../core/barrio_context/tenant_session.dart';
import '../../../../core/database_sqlite/local_id.dart';
import '../../../../core/location/gps_service.dart';
import '../../domain/entities/vulnerable_report_entity.dart';
import '../../domain/repositories/emergency_repository.dart';

/// Punto único donde la UI de emergencia obtiene sus datos.
///
/// Mientras Dev 2 termina la tabla local `vulnerable_reports`, se usa
/// [InMemoryEmergencyRepository] (los SOS viven mientras la app está abierta).
/// Para conectar SQLite + sync basta una línea en `main.dart`:
/// `EmergencyReports.use(EmergencyRepositoryImpl());`
class EmergencyReports {
  EmergencyReports._();

  static EmergencyRepository _repository = InMemoryEmergencyRepository();

  static EmergencyRepository get repository => _repository;

  /// true mientras se usa el repositorio temporal en memoria.
  static bool get isTemporary => _repository is InMemoryEmergencyRepository;

  static void use(EmergencyRepository repository) => _repository = repository;
}

/// Ubicación usada para ordenar por cercanía y para el SOS.
class HelpLocation {
  const HelpLocation({required this.lat, required this.lng, required this.fromGps});

  final double lat;
  final double lng;

  /// false = se usó el centro del barrio porque el GPS no respondió.
  final bool fromGps;
}

/// Cómo se obtiene la ubicación para pedir ayuda (reemplazable en pruebas).
typedef HelpLocationResolver = Future<HelpLocation> Function();

/// Obtiene la ubicación del GPS y, si falla (permiso, apagado, demora),
/// usa el centro del barrio: la app nunca se queda sin poder pedir ayuda.
class HelpLocator {
  HelpLocator._();

  static HelpLocationResolver resolve = _gpsWithFallback;

  /// Igual que [resolve] pero sin mostrar el diálogo de permiso: el mapa y
  /// las distancias no deben pedir la ubicación al abrir la app (se pide al
  /// pedir ayuda o publicar, cuando se entiende para qué es).
  static Future<HelpLocation> resolveQuietly() =>
      identical(resolve, _defaultResolver) ? _gpsWithFallback(ask: false) : resolve();

  static const HelpLocationResolver _defaultResolver = _gpsWithFallback;

  static Future<HelpLocation> _gpsWithFallback({bool ask = true}) async {
    try {
      final c = await GpsService().getCurrentCoordinates(
        timeLimit: const Duration(seconds: 6),
        askPermission: ask,
      );
      return HelpLocation(lat: c.latitude, lng: c.longitude, fromGps: true);
    } catch (_) {
      final session = TenantSession.instance;
      return HelpLocation(lat: session.centerLat, lng: session.centerLng, fromGps: false);
    }
  }
}

/// Implementación temporal en memoria (también se usa en los tests).
class InMemoryEmergencyRepository implements EmergencyRepository {
  InMemoryEmergencyRepository({List<VulnerableReport>? seed}) {
    if (seed != null) _reports.addAll(seed);
  }

  final List<VulnerableReport> _reports = [];
  final StreamController<void> _changes = StreamController<void>.broadcast();

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<List<VulnerableReport>> activeReports(String tenantId) async =>
      _reports.where((r) => r.tenantId == tenantId).toList(growable: false);

  @override
  Future<VulnerableReport> createSos({
    required String tenantId,
    required String reporterUserId,
    required String vulnerabilityType,
    required String urgencyLevel,
    required String description,
    required double lat,
    required double lng,
    String? otherTypeLabel,
    int? peopleCount,
    bool? hasInjured,
    List<String> vulnerableGroups = const [],
    String? contactPhone,
  }) async {
    if (!VulnerabilityType.values.contains(vulnerabilityType)) {
      throw ArgumentError.value(vulnerabilityType, 'vulnerabilityType');
    }
    if (!UrgencyLevel.values.contains(urgencyLevel)) {
      throw ArgumentError.value(urgencyLevel, 'urgencyLevel');
    }
    final report = VulnerableReport(
      id: LocalId.generate(),
      tenantId: tenantId,
      reporterUserId: reporterUserId,
      urgencyLevel: urgencyLevel,
      vulnerabilityType: vulnerabilityType,
      description: description.trim().isEmpty
          ? VulnerabilityType.labels[vulnerabilityType]!
          : description.trim(),
      lat: lat,
      lng: lng,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
      isPending: true,
      otherTypeLabel: otherTypeLabel,
      peopleCount: peopleCount,
      hasInjured: hasInjured,
      vulnerableGroups: vulnerableGroups,
      contactPhone: contactPhone,
    );
    _reports.add(report);
    _changes.add(null);
    return report;
  }

  @override
  Future<VulnerableReport> offerHelp({
    required String tenantId,
    required String reportId,
    required String helperUserId,
  }) async {
    final i = _reports.indexWhere((r) => r.id == reportId && r.tenantId == tenantId);
    if (i < 0) throw ArgumentError.value(reportId, 'reportId', 'Reporte no encontrado');
    final updated = _reports[i].copyWith(
      status: ReportStatus.vecinosEnCamino,
      helperUserId: helperUserId,
      isPending: true,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );
    _reports[i] = updated;
    _changes.add(null);
    return updated;
  }
}
