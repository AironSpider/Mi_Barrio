import 'package:flutter/material.dart';

/// Botón flotante (+) de publicación rápida — Clic 1 del flujo de 3 clics.
///
/// - Modo Día a Día: "Publicar" (verde).
/// - Modo Emergencia: "Ayuda" (naranja, ícono SOS).
///
/// Extendido con texto (no solo ícono) para que cualquier vecino,
/// incluidos adultos mayores, entienda qué hace sin adivinar.
class QuickPublishFab extends StatelessWidget {
  const QuickPublishFab({
    super.key,
    required this.isEmergencyMode,
    required this.onPressed,
  });

  final bool isEmergencyMode;
  final VoidCallback? onPressed;

  static const fabKey = ValueKey('quick_publish_fab');

  @override
  Widget build(BuildContext context) {
    final label = isEmergencyMode ? 'Ayuda' : 'Publicar';
    final hint = isEmergencyMode
        ? 'Abre el reporte rápido de emergencia'
        : 'Publica un favor, préstamo u oficio en tres pasos';

    return Semantics(
      button: true,
      label: label,
      hint: hint,
      excludeSemantics: true,
      child: FloatingActionButton.extended(
        key: fabKey,
        heroTag: 'quick_publish_fab',
        tooltip: hint,
        onPressed: onPressed,
        icon: Icon(isEmergencyMode ? Icons.sos_rounded : Icons.add_rounded),
        label: Text(label),
      ),
    );
  }
}
