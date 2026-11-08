import 'dart:math' as math;

/// Qué publicó un vecino (para el color del marcador y la lista al tocarlo).
enum PinItemKind { sos, favor, service }

/// Una publicación dentro del marcador de su autor.
class PinItem {
  const PinItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.lat,
    required this.lng,
    required this.updatedAt,
    this.subtitle,
    this.canOfferHelp = false,
    this.source,
  });

  /// La publicación o el servicio completo, para abrir su detalle desde el
  /// mapa (null en los SOS: se atienden con "Voy en camino").
  final Object? source;

  final String id;
  final PinItemKind kind;
  final String title;
  final String? subtitle;
  final double lat;
  final double lng;

  /// ISO-8601: la más reciente decide dónde se dibuja a la persona.
  final String updatedAt;

  /// SOS ajeno que todavía necesita apoyo ("Voy en camino").
  final bool canOfferHelp;
}

/// Un vecino en el mapa, con todas sus publicaciones activas.
class NeighborPin {
  const NeighborPin({
    required this.userId,
    required this.label,
    required this.lat,
    required this.lng,
    required this.items,
    required this.isMe,
  });

  final String userId;
  final String label;
  final double lat;
  final double lng;
  final List<PinItem> items;
  final bool isMe;

  /// El SOS manda: un vecino que pide ayuda se ve rojo aunque también ofrezca algo.
  PinItemKind get mainKind {
    if (items.any((i) => i.kind == PinItemKind.sos)) return PinItemKind.sos;
    if (items.any((i) => i.kind == PinItemKind.service)) return PinItemKind.service;
    return PinItemKind.favor;
  }
}

/// Agrupa publicaciones por persona y ubica a cada una donde publicó lo último
/// (prioriza el SOS: es lo que hay que encontrar rápido).
///
/// Muchas publicaciones usan el centro del barrio como ubicación: si varias
/// personas caen en el mismo punto, se reparten en un círculo pequeño para
/// que todos los marcadores se puedan tocar.
class NeighborPins {
  NeighborPins._();

  /// Separación entre marcadores que coinciden (≈ 30 m).
  static const spreadDegrees = 0.00027;

  static List<NeighborPin> build({
    required Map<String, List<PinItem>> itemsByUser,
    required String myUserId,
    Map<String, String> labels = const {},
  }) {
    final pins = <NeighborPin>[];
    final ids = itemsByUser.keys.toList()..sort();
    for (final userId in ids) {
      final items = [...itemsByUser[userId]!]
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      if (items.isEmpty) continue;
      final anchor = items.firstWhere(
        (i) => i.kind == PinItemKind.sos,
        orElse: () => items.first,
      );
      pins.add(NeighborPin(
        userId: userId,
        label: userId == myUserId ? 'Tú' : labels[userId] ?? 'Vecino',
        lat: anchor.lat,
        lng: anchor.lng,
        items: items,
        isMe: userId == myUserId,
      ));
    }
    return _spread(pins);
  }

  static List<NeighborPin> _spread(List<NeighborPin> pins) {
    final byPoint = <String, List<NeighborPin>>{};
    for (final p in pins) {
      final key = '${p.lat.toStringAsFixed(5)},${p.lng.toStringAsFixed(5)}';
      byPoint.putIfAbsent(key, () => []).add(p);
    }
    return [
      for (final group in byPoint.values)
        for (var i = 0; i < group.length; i++)
          group.length == 1
              ? group[i]
              : NeighborPin(
                  userId: group[i].userId,
                  label: group[i].label,
                  lat: group[i].lat +
                      spreadDegrees * math.sin(2 * math.pi * i / group.length),
                  lng: group[i].lng +
                      spreadDegrees * math.cos(2 * math.pi * i / group.length),
                  items: group[i].items,
                  isMe: group[i].isMe,
                ),
    ];
  }
}
