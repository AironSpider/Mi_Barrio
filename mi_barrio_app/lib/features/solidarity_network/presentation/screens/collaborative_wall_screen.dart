import 'package:flutter/material.dart';

import '../../../../core/ui_kit/feature_placeholder.dart';

/// Muro colaborativo sin dinero (Módulo 2).
/// Contenido real: Sprint 5 (Dev 3).
class CollaborativeWallScreen extends StatelessWidget {
  const CollaborativeWallScreen({super.key, this.criticalResourcesOnly = false});

  /// En Modo Emergencia prioriza recursos críticos (agua, botiquín, generador).
  final bool criticalResourcesOnly;

  @override
  Widget build(BuildContext context) {
    return FeaturePlaceholder(
      icon: Icons.volunteer_activism_rounded,
      title: criticalResourcesOnly ? 'Recursos críticos' : 'Muro solidario',
      description: criticalResourcesOnly
          ? 'Agua, botiquines, generadores y espacios compartidos por tus vecinos.'
          : 'Préstamos, donaciones e intercambio de habilidades, sin dinero.',
    );
  }
}
