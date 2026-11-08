import '../../../../shared/local_distance.dart';

/// Texto corto bajo cada favor del muro: "hace 2 h · a 300 m".
///
/// Cuando Dev 2 publique `TimeAgo.label` en `lib/shared/`, [timeAgo] puede
/// delegar en él sin cambiar la pantalla.
class PostMetaLabel {
  PostMetaLabel._();

  /// "hace un momento", "hace 5 min", "hace 2 h", "ayer", "hace 3 días".
  /// Devuelve null si la fecha no se puede leer.
  static String? timeAgo(String updatedAtIso, {DateTime? now}) {
    final date = DateTime.tryParse(updatedAtIso);
    if (date == null) return null;
    final ahora = (now ?? DateTime.now()).toUtc();
    final diff = ahora.difference(date.toUtc());
    if (diff.inMinutes < 1) return 'hace un momento';
    if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'hace ${diff.inHours} h';
    if (diff.inDays == 1) return 'ayer';
    if (diff.inDays < 30) return 'hace ${diff.inDays} días';
    return 'hace más de un mes';
  }

  /// "a 300 m", "a 2,4 km"; "muy cerca" a menos de 50 m.
  static String distance(double km) {
    if (km < 0.05) return 'muy cerca';
    return 'a ${LocalDistance.label(km)}';
  }

  /// Une ambos con " · ". Si falta un dato, muestra solo el otro.
  static String? build({
    required String updatedAtIso,
    double? distanceKm,
    DateTime? now,
  }) {
    final parts = [
      ?timeAgo(updatedAtIso, now: now),
      if (distanceKm != null) distance(distanceKm),
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}
