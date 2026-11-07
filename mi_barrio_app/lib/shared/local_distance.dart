import 'dart:math' as math;

/// Distancia entre dos coordenadas GPS, sin internet ni servicios de mapas.
class LocalDistance {
  LocalDistance._();

  static const earthRadiusKm = 6371.0;

  /// Distancia en kilómetros (fórmula de haversine).
  static double km(double lat1, double lng1, double lat2, double lng2) {
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(_rad(lat1)) * math.cos(_rad(lat2)) * math.pow(math.sin(dLng / 2), 2);
    return 2 * earthRadiusKm * math.asin(math.min(1, math.sqrt(a)));
  }

  /// Texto corto para la UI: "350 m" o "2,4 km".
  static String label(double km) {
    if (km < 1) return '${(km * 1000).round()} m';
    return '${km.toStringAsFixed(1).replaceAll('.', ',')} km';
  }

  static double _rad(double deg) => deg * math.pi / 180;
}
