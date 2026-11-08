import 'package:flutter/material.dart';

import 'app_theme.dart';

class FilterPill extends StatelessWidget {
  const FilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final texto = Theme.of(context).textTheme;

    final colores = MiBarrioColors.of(context);
    // Seleccionada: celeste suave #E0F2FE, texto y borde azul #075985 (6.6:1)
    // y un ✓, para que no dependa solo del color.
    final fondo = selected ? colores.pill : AppPalette.card;
    final frente = selected ? colores.onPill : esquema.onSurfaceVariant;
    final borde = selected ? colores.onPill : esquema.outlineVariant;
    final iconoFinal = selected ? Icons.check_rounded : icon;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: fondo,
        shape: StadiumBorder(side: BorderSide(color: borde)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AppTheme.minTouchTarget,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (iconoFinal != null) ...[
                    Icon(iconoFinal, size: 18, color: frente),
                    const SizedBox(width: 6),
                  ],
                  Text(label, style: texto.labelLarge?.copyWith(color: frente)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class FilterPillBar extends StatelessWidget {
  const FilterPillBar({
    super.key,
    required this.options,
    required this.selected,
    required this.onToggle,
  });

  final Map<String, String> options;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final entradas = options.entries.toList();

    return SizedBox(
      height: 60,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: entradas.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final entrada = entradas[i];
          return Center(
            child: FilterPill(
              label: entrada.value,
              selected: selected.contains(entrada.key),
              onTap: () => onToggle(entrada.key),
            ),
          );
        },
      ),
    );
  }
}
