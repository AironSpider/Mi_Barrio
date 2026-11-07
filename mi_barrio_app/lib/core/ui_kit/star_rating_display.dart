import 'package:flutter/material.dart';

import 'app_theme.dart';

class StarRatingDisplay extends StatelessWidget {
  const StarRatingDisplay({
    super.key,
    required this.rating,
    this.count,
    this.size = 20,
    this.showValue = true,
  });

  final double rating;
  final int? count;
  final double size;
  final bool showValue;

  IconData _icono(double valor, int posicion) {
    if (valor >= posicion) return Icons.star_rounded;
    if (valor >= posicion - 0.5) return Icons.star_half_rounded;
    return Icons.star_outline_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final valor = rating.clamp(0, 5).toDouble();
    final texto = Theme.of(context).textTheme;
    final esquema = Theme.of(context).colorScheme;
    final sinCalificar = valor == 0 && (count == null || count == 0);

    final etiqueta = sinCalificar
        ? 'Sin calificaciones todavía'
        : count == null
        ? 'Calificación ${valor.toStringAsFixed(1)} de 5'
        : 'Calificación ${valor.toStringAsFixed(1)} de 5, $count opiniones';

    return Semantics(
      label: etiqueta,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 1; i <= 5; i++)
            Icon(
              _icono(valor, i),
              size: size,
              color: valor >= i - 0.5
                  ? MiBarrioColors.of(context).starFilled
                  : MiBarrioColors.of(context).starEmpty,
            ),
          if (showValue) ...[
            const SizedBox(width: 6),
            Text(
              sinCalificar ? 'Sin calificar' : valor.toStringAsFixed(1),
              style: texto.labelLarge?.copyWith(
                color: esquema.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (count != null && !sinCalificar)
              Text(
                ' ($count)',
                style: texto.bodyMedium?.copyWith(
                  color: esquema.onSurfaceVariant,
                ),
              ),
          ],
        ],
      ),
    );
  }
}
