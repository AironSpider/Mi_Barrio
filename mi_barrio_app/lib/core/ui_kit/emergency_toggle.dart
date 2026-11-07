import 'package:flutter/material.dart';

import 'app_theme.dart';

class EmergencyToggle extends StatelessWidget {
  const EmergencyToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  static const switchKey = ValueKey('emergency_toggle_switch');

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final texto = Theme.of(context).textTheme;

    return MergeSemantics(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        decoration: BoxDecoration(
          color: value ? AppPalette.emergencyBackground : AppPalette.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: value ? AppPalette.emergencyStripe : esquema.outlineVariant,
            width: value ? 2 : 1,
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onChanged == null ? null : () => onChanged!(!value),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 28,
                    color: value
                        ? AppPalette.emergencyOnPrimaryContainer
                        : esquema.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Modo emergencia', style: texto.titleMedium),
                        Text(
                          value
                              ? 'Activo: lo urgente aparece primero'
                              : 'Desactivado',
                          style: texto.bodyMedium?.copyWith(
                            color: esquema.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(key: switchKey, value: value, onChanged: onChanged),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
