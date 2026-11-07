import 'package:flutter/material.dart';

/// Marco del podio "Prioridad 1-3" en modo emergencia.
/// Si [priority] es null devuelve la tarjeta tal cual.
class PriorityPodiumFrame extends StatelessWidget {
  const PriorityPodiumFrame({
    super.key,
    required this.priority,
    required this.child,
  });

  final int? priority;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = priority;
    if (p == null) return child;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.primary, width: 2),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Chip(
              avatar: Icon(Icons.emergency_rounded, color: scheme.primary),
              label: Text('Prioridad $p'),
            ),
          ),
          child,
        ],
      ),
    );
  }
}