import 'package:flutter/material.dart';

import '../../../../core/ui_kit/app_theme.dart';
import '../../domain/repositories/emergency_repository.dart';
import '../providers/emergency_provider.dart';
import 'humanitarian_board_screen.dart';

/// Pestaña "Mapa": pedidos de ayuda en modo lista.
/// - "Más cerca": del más cercano al más lejano (GPS o centro del barrio).
/// - "Más urgente": el tablero humanitario ordenado por urgencia.
class EmergencyMapScreen extends StatefulWidget {
  const EmergencyMapScreen({super.key, this.isEmergencyMode = false, this.repository});

  final bool isEmergencyMode;
  final EmergencyRepository? repository;

  static const proximityKey = ValueKey('map_sort_proximity');
  static const urgencyKey = ValueKey('map_sort_urgency');

  @override
  State<EmergencyMapScreen> createState() => _EmergencyMapScreenState();
}

class _EmergencyMapScreenState extends State<EmergencyMapScreen> {
  bool _byDistance = true;
  HelpLocation? _location;

  @override
  void initState() {
    super.initState();
    HelpLocator.resolve().then((loc) {
      if (mounted) setState(() => _location = loc);
    });
  }

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    final esquema = Theme.of(context).colorScheme;
    final loc = _location;

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Mapa de ayuda', style: texto.headlineSmall),
        const SizedBox(height: 4),
        Row(
          children: [
            Icon(
              loc == null
                  ? Icons.location_searching_rounded
                  : loc.fromGps
                  ? Icons.my_location_rounded
                  : Icons.location_city_rounded,
              size: 20,
              color: esquema.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                loc == null
                    ? 'Buscando tu ubicación…'
                    : loc.fromGps
                    ? 'Distancias desde tu ubicación actual.'
                    : 'Sin GPS: distancias desde el centro del barrio.',
                style: texto.bodyMedium?.copyWith(color: esquema.onSurfaceVariant),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SegmentedButton<bool>(
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(minimumSize: const Size(48, 52)),
          segments: const [
            ButtonSegment(
              value: true,
              label: Text('Más cerca', key: EmergencyMapScreen.proximityKey),
              icon: Icon(Icons.near_me_rounded),
            ),
            ButtonSegment(
              value: false,
              label: Text('Más urgente', key: EmergencyMapScreen.urgencyKey),
              icon: Icon(Icons.priority_high_rounded),
            ),
          ],
          selected: {_byDistance},
          onSelectionChanged: (v) => setState(() => _byDistance = v.first),
        ),
        const SizedBox(height: 8),
      ],
    );

    return HumanitarianBoardScreen(
      key: ValueKey('board_${_byDistance ? 'distance' : 'urgency'}'),
      // El modo se toma del tema: la pestaña se construye una sola vez en el shell.
      isEmergencyMode: widget.isEmergencyMode || MiBarrioColors.of(context).isEmergency,
      sortByDistance: _byDistance,
      repository: widget.repository,
      header: header,
    );
  }
}
