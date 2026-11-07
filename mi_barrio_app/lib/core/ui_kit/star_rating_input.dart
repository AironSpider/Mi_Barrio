import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_theme.dart';

class StarRatingInput extends StatelessWidget {
  const StarRatingInput({
    super.key,
    required this.value,
    required this.onChanged,
    this.size = 40,
  });

  final int value;
  final ValueChanged<int>? onChanged;
  final double size;

  static const List<String> etiquetas = [
    'Toca una estrella',
    'Malo',
    'Regular',
    'Bueno',
    'Muy bueno',
    'Excelente',
  ];

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    final esquema = Theme.of(context).colorScheme;
    final actual = value.clamp(0, 5);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 1; i <= 5; i++)
              _Estrella(
                posicion: i,
                activa: i <= actual,
                size: size,
                onTap: onChanged == null
                    ? null
                    : () {
                        HapticFeedback.selectionClick();
                        onChanged!(i);
                      },
              ),
          ],
        ),
        const SizedBox(height: 4),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Text(
            etiquetas[actual],
            key: ValueKey(actual),
            style: texto.titleMedium?.copyWith(
              color: actual == 0
                  ? esquema.onSurfaceVariant
                  : AppPalette.orangeText,
            ),
          ),
        ),
      ],
    );
  }
}

class _Estrella extends StatelessWidget {
  const _Estrella({
    required this.posicion,
    required this.activa,
    required this.size,
    required this.onTap,
  });

  final int posicion;
  final bool activa;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: activa,
      label: posicion == 1 ? '1 estrella' : '$posicion estrellas',
      excludeSemantics: true,
      child: IconButton(
        onPressed: onTap,
        constraints: const BoxConstraints(
          minWidth: AppTheme.minTouchTarget,
          minHeight: AppTheme.minTouchTarget,
        ),
        icon: AnimatedScale(
          scale: activa ? 1.12 : 1.0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutBack,
          child: Icon(
            activa ? Icons.star_rounded : Icons.star_outline_rounded,
            size: size,
            color: activa ? AppPalette.starFilled : AppPalette.starEmpty,
          ),
        ),
      ),
    );
  }
}