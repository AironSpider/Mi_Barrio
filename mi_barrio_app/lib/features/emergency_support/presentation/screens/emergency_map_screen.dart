import 'package:flutter/material.dart';

import '../../../../core/ui_kit/feature_placeholder.dart';

/// Mapa / lista por cercanía de casos críticos.
/// Contenido real: Sprint 11 (Dev 3).
class EmergencyMapScreen extends StatelessWidget {
  const EmergencyMapScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholder(
      icon: Icons.map_rounded,
      title: 'Mapa de ayuda',
      description: 'Pedidos, recursos y vecinos vulnerables cerca de ti, '
          'del más cercano al más lejano.',
    );
  }
}
