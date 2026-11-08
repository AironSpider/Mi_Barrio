import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'app_theme.dart';

/// Interruptor de emergencia de los formularios para publicar.
/// Encendido se ve naranja (fondo, ícono y switch); viene encendido cuando
/// la app está en modo emergencia.
///
/// - Ofrezco: "Atiendo en emergencias".
/// - Necesito: "Es una emergencia".
class EmergencySwitchTile extends StatelessWidget {
  const EmergencySwitchTile({
    super.key,
    required this.value,
    required this.onChanged,
    required this.isNeed,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  /// true = es un pedido (Necesito); false = es una oferta (Ofrezco).
  final bool isNeed;

  static String titleFor({required bool isNeed}) =>
      isNeed ? 'Es una emergencia' : 'Atiendo en emergencias';

  @override
  Widget build(BuildContext context) {
    final subtitle = isNeed
        ? 'Tu pedido aparece primero para los vecinos que ayudan en emergencias.'
        : 'Apareces primero cuando el barrio está en emergencia.';
    // Material (no DecoratedBox): el ListTile pinta su toque sobre él.
    return Material(
      color: value ? AppPalette.emergencyBackground : AppPalette.card,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: value ? AppPalette.brandOrange : AppPalette.pillBorder,
        ),
      ),
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        secondary: FaIcon(
          FontAwesomeIcons.triangleExclamation,
          color: value ? AppPalette.emergencyPrimary : AppPalette.filterIcon,
        ),
        title: Text(titleFor(isNeed: isNeed)),
        subtitle: Text(subtitle),
        activeThumbColor: Colors.white,
        activeTrackColor: AppPalette.emergencyPrimary,
      ),
    );
  }
}
