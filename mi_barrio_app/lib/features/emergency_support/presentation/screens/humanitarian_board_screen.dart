import 'package:flutter/material.dart';

import '../../../../core/ui_kit/feature_placeholder.dart';

/// Tablero de ayuda humanitaria.
/// Contenido real: Sprint 8 (Dev 3).
class HumanitarianBoardScreen extends StatelessWidget {
  const HumanitarianBoardScreen({super.key, required this.isEmergencyMode});

  /// Fuera de emergencia funciona como pantalla de preparación.
  final bool isEmergencyMode;

  @override
  Widget build(BuildContext context) {
    return FeaturePlaceholder(
      icon: isEmergencyMode ? Icons.sos_rounded : Icons.health_and_safety_rounded,
      title: isEmergencyMode ? 'Pedidos de ayuda' : 'Barrio preparado',
      description: isEmergencyMode
          ? 'Vecinos que necesitan apoyo ahora, ordenados por urgencia.'
          : 'No hay una emergencia activa. Aquí verás los grupos de apoyo '
              'y cómo ayudar si ocurre una.',
    );
  }
}
