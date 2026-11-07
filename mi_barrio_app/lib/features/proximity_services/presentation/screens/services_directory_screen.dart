import 'package:flutter/material.dart';

import '../../../../core/ui_kit/feature_placeholder.dart';

/// Directorio de Oficios con "Visto Bueno Vecinal" (Módulo 1).
/// Contenido real: Sprint 6 (Dev 3).
class ServicesDirectoryScreen extends StatelessWidget {
  const ServicesDirectoryScreen({super.key, this.emergencyOnly = false});

  /// En Modo Emergencia muestra solo oficios disponibles para soporte crítico.
  final bool emergencyOnly;

  @override
  Widget build(BuildContext context) {
    return FeaturePlaceholder(
      icon: Icons.handyman_rounded,
      title: emergencyOnly ? 'Oficios de apoyo' : 'Oficios del barrio',
      description: emergencyOnly
          ? 'Electricistas, gasfiteros y personal de salud disponibles ahora.'
          : 'Gasfitería, carpintería, electricidad, clases y más, '
              'recomendados por tus vecinos.',
    );
  }
}
