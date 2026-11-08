import 'package:flutter/material.dart';

import '../../../../core/ui_kit/app_theme.dart';
import '../../domain/repositories/emergency_repository.dart';
import '../providers/emergency_provider.dart';
import '../widgets/nearby_posts_list.dart';
import '../widgets/neighbor_map.dart';
import 'humanitarian_board_screen.dart';

/// Pestaña "Mapa".
/// - **Mapa** (por defecto): cada vecino que publicó, con sus pedidos de
///   ayuda, favores y servicios ([NeighborMap]).
/// - **Lista**: los pedidos de ayuda, por cercanía ("Más cerca") o por
///   urgencia ("Más urgente"), y debajo los favores y servicios (lo mismo
///   que el mapa).
class EmergencyMapScreen extends StatefulWidget {
  const EmergencyMapScreen({
    super.key,
    this.isEmergencyMode = false,
    this.repository,
    this.startInList = false,
  });

  final bool isEmergencyMode;
  final EmergencyRepository? repository;

  /// true = abre directamente en la vista de lista.
  final bool startInList;

  static const mapViewKey = ValueKey('map_view_map');
  static const listViewKey = ValueKey('map_view_list');

  static const proximityKey = ValueKey('map_sort_proximity');
  static const urgencyKey = ValueKey('map_sort_urgency');

  @override
  State<EmergencyMapScreen> createState() => _EmergencyMapScreenState();
}

class _EmergencyMapScreenState extends State<EmergencyMapScreen> {
  bool _byDistance = true;
  late bool _asList = widget.startInList;
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

    final viewToggle = SegmentedButton<bool>(
      showSelectedIcon: false,
      style: SegmentedButton.styleFrom(minimumSize: const Size(48, 52)),
      segments: const [
        ButtonSegment(
          value: false,
          label: Text('Mapa', key: EmergencyMapScreen.mapViewKey),
          icon: Icon(Icons.map_rounded),
        ),
        ButtonSegment(
          value: true,
          label: Text('Lista', key: EmergencyMapScreen.listViewKey),
          icon: Icon(Icons.view_list_rounded),
        ),
      ],
      selected: {_asList},
      onSelectionChanged: (v) => setState(() => _asList = v.first),
    );
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Mapa de ayuda', style: texto.headlineSmall),
        const SizedBox(height: 8),
        viewToggle,
      ],
    );
    final repository = widget.repository ?? EmergencyReports.repository;

    if (!_asList) {
      // El mapa ocupa el resto de la pantalla. Con letra muy grande no cabe:
      // entonces la vista se desplaza y el mapa mantiene una altura mínima.
      final textScale = MediaQuery.textScalerOf(context).scale(1);
      return LayoutBuilder(
        builder: (context, constraints) {
          const minMap = 360.0;
          final headerHeight = (32 + 8 + 52 + 12) * textScale;
          final available = constraints.maxHeight - 16 - 96 - headerHeight;
          final fits = available >= minMap;
          return ListView(
            physics: fits ? const NeverScrollableScrollPhysics() : null,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              title,
              const SizedBox(height: 12),
              SizedBox(
                height: fits ? available : minMap,
                child: NeighborMap(repository: repository, location: loc),
              ),
            ],
          );
        },
      );
    }

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        title,
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
      // Lo mismo que el mapa: favores y servicios, del más cercano al más lejano.
      footer: NearbyPostsList(location: loc),
    );
  }
}
