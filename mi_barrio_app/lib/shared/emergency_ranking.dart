import '../features/proximity_services/data/models/service_model.dart';
import '../features/solidarity_network/data/models/solidarity_post_model.dart';
import 'local_distance.dart';

/// Un elemento ya ordenado por el ranking de emergencia.
///
/// [position] empieza en 1. [priority] es 1, 2 o 3 si el elemento va en el
/// podio "Prioridad 1-3" (la UI muestra el chip con ese número); si no, null.
class Ranked<T> {
  const Ranked({
    required this.item,
    required this.position,
    this.priority,
    this.distanceKm,
  });

  final T item;
  final int position;
  final int? priority;

  /// Distancia al vecino; null si no se conoce su ubicación.
  final double? distanceKm;

  bool get isPodium => priority != null;
}

/// Orden de "qué ayuda primero" durante una emergencia. Funciona sin internet:
/// solo usa lo que ya está en SQLite y la ubicación del vecino.
///
/// Uso en pantalla:
/// ```dart
/// final ranked = EmergencyRanking.rankServices(services, lat: lat, lng: lng);
/// final podio = ranked.where((r) => r.isPodium); // máx. 3
/// ```
class EmergencyRanking {
  EmergencyRanking._();

  static const podiumSize = 3;

  /// Oficios: disponible en emergencia → categoría SOPORTE_EMERGENCIA →
  /// mejor promedio de estrellas (sin calificar va al final) → más cerca.
  ///
  /// Los borrados no aparecen. Si [lat]/[lng] son null no se usa la distancia.
  static List<Ranked<LocalServiceModel>> rankServices(
    Iterable<LocalServiceModel> services, {
    double? lat,
    double? lng,
  }) {
    final rows = [
      for (final s in services)
        if (!s.isDeleted) (item: s, km: _distance(lat, lng, s.lat, s.lng)),
    ];

    rows.sort((a, b) {
      final x = a.item;
      final y = b.item;
      return _firstNonZero([
        _trueFirst(x.isAvailableInEmergency, y.isAvailableInEmergency),
        _trueFirst(
          x.category == ServiceCategory.soporteEmergencia,
          y.category == ServiceCategory.soporteEmergencia,
        ),
        _higherFirst(x.ratingAvg, y.ratingAvg),
        _nearerFirst(a.km, b.km),
        x.id.compareTo(y.id), // desempate estable
      ]);
    });

    return [
      for (var i = 0; i < rows.length; i++)
        Ranked(
          item: rows[i].item,
          position: i + 1,
          priority: i < podiumSize ? i + 1 : null,
          distanceKm: rows[i].km,
        ),
    ];
  }

  /// Favores: contexto de emergencia o RECURSO_CRITICO → DISPONIBLE antes que
  /// EN_COORDINACION → más cerca → más reciente.
  ///
  /// Los borrados no aparecen. Los COMPLETADO ya no necesitan ayuda: van
  /// siempre al final y nunca ocupan el podio.
  static List<Ranked<SolidarityPostModel>> rankPosts(
    Iterable<SolidarityPostModel> posts, {
    double? lat,
    double? lng,
  }) {
    final rows = [
      for (final p in posts)
        if (!p.isDeleted) (item: p, km: _distance(lat, lng, p.lat, p.lng)),
    ];

    rows.sort((a, b) {
      final x = a.item;
      final y = b.item;
      return _firstNonZero([
        _trueFirst(!_isDone(x), !_isDone(y)),
        _trueFirst(isUrgentPost(x), isUrgentPost(y)),
        _trueFirst(
          x.status == SolidarityStatus.disponible,
          y.status == SolidarityStatus.disponible,
        ),
        _nearerFirst(a.km, b.km),
        _newerFirst(x.updatedAt, y.updatedAt),
        x.id.compareTo(y.id),
      ]);
    });

    return [
      for (var i = 0; i < rows.length; i++)
        Ranked(
          item: rows[i].item,
          position: i + 1,
          priority: i < podiumSize && !_isDone(rows[i].item) ? i + 1 : null,
          distanceKm: rows[i].km,
        ),
    ];
  }

  static bool _isDone(SolidarityPostModel post) =>
      post.status == SolidarityStatus.completado;

  /// Un favor es urgente si se publicó en emergencia o es un recurso crítico.
  static bool isUrgentPost(SolidarityPostModel post) =>
      post.isEmergencyContext ||
      post.modality == SolidarityModality.recursoCritico;

  static double? _distance(double? lat, double? lng, double toLat, double toLng) =>
      lat == null || lng == null ? null : LocalDistance.km(lat, lng, toLat, toLng);

  static int _firstNonZero(List<int> results) =>
      results.firstWhere((r) => r != 0, orElse: () => 0);

  static int _trueFirst(bool a, bool b) => a == b ? 0 : (a ? -1 : 1);

  /// null (sin dato) siempre al final.
  static int _higherFirst(double? a, double? b) {
    if (a == b) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return b.compareTo(a);
  }

  static int _nearerFirst(double? a, double? b) {
    if (a == b) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return a.compareTo(b);
  }

  static int _newerFirst(String a, String b) {
    final da = DateTime.tryParse(a);
    final db = DateTime.tryParse(b);
    if (da == null || db == null) return b.compareTo(a);
    return db.compareTo(da);
  }
}
