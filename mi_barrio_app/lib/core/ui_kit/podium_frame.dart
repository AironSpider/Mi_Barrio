import 'package:flutter/material.dart';

/// Marco del podio de emergencia: borde de color de énfasis y chip
/// "Prioridad N" con ícono y texto (no depende solo del color).
class PodiumFrame extends StatelessWidget {
  const PodiumFrame({super.key, required this.priority, required this.child});

  /// 1, 2 o 3.
  final int priority;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;
    return Semantics(
      container: true,
      label: 'Prioridad $priority',
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
        decoration: BoxDecoration(
          border: Border.all(color: color, width: 3),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 4, bottom: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.emergency_rounded, size: 22, color: color),
                  const SizedBox(width: 6),
                  Text(
                    'Prioridad $priority',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            child,
          ],
        ),
      ),
    );
  }
}
