import 'package:flutter/material.dart';

import '../../../../core/ui_kit/app_theme.dart';
import '../../../../core/ui_kit/star_rating_display.dart';
import 'visto_bueno_badge.dart';

class ServiceCard extends StatelessWidget {
  const ServiceCard({
    super.key,
    required this.title,
    required this.categoryLabel,
    required this.categoryIcon,
    required this.endorsementsCount,
    required this.isEndorsed,
    this.description,
    this.isPending = false,
    this.isAvailableInEmergency = false,
    this.ratingAvg,
    this.isOwn = false,
    this.priceText,
    this.photoCount = 0,
    this.onEndorse,
    this.onTap,
    this.isNeed = false,
    this.publisherBadge,
    this.isUnderReview = false,
  });

  /// true = es un pedido ("Necesito"): no lleva estrellas ni Visto Bueno.
  final bool isNeed;

  /// "Vecino" o "Negocio": quién lo publica.
  final String? publisherBadge;

  /// Propio y oculto por reportes, hasta que el administrador lo revise.
  final bool isUnderReview;

  /// Promedio de estrellas (null = sin calificaciones con estrellas).
  final double? ratingAvg;

  /// true = es un servicio del propio vecino.
  final bool isOwn;

  /// "S/ 30 la visita" (null = sin precio publicado).
  final String? priceText;
  final int photoCount;

  final String title;
  final String categoryLabel;
  final IconData categoryIcon;
  final String? description;
  final int endorsementsCount;
  final bool isEndorsed;
  final bool isPending;
  final bool isAvailableInEmergency;
  final VoidCallback? onEndorse;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final texto = Theme.of(context).textTheme;
    final colores = MiBarrioColors.of(context);

    // Lo propio se distingue con fondo verde agua y la etiqueta "Tuyo"
    // (no solo con color); al tocarlo, gris suave.
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6),
      color: isOwn ? colores.accentSoft : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: isOwn
              ? colores.brand.withValues(alpha: 0.35)
              : esquema.outline.withValues(alpha: 0.35),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        highlightColor: isOwn ? AppPalette.filterActiveBackground : null,
        splashColor: isOwn ? AppPalette.filterActiveBackground : null,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isOwn ? Colors.white : esquema.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      categoryIcon,
                      size: 28,
                      color: esquema.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              categoryLabel,
                              style: texto.labelMedium?.copyWith(
                                color: esquema.onSurfaceVariant,
                              ),
                            ),
                            if (publisherBadge != null)
                              _Badge(text: publisherBadge!),
                            if (isOwn) const _Badge(text: 'Tuyo', strong: true),
                            if (isNeed) const _Badge(text: 'Necesita', need: true),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          title,
                          style: texto.titleMedium,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (ratingAvg != null && !isNeed) ...[
                          const SizedBox(height: 4),
                          StarRatingDisplay(
                            rating: ratingAvg!,
                            count: endorsementsCount,
                            size: 18,
                          ),
                        ],
                        if (isOwn && isUnderReview) ...[
                          const SizedBox(height: 4),
                          Text(
                            'En revisión: tus vecinos no lo ven por ahora',
                            style: texto.labelMedium?.copyWith(
                              color: colores.urgencyCritical,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (isPending)
                    Tooltip(
                      message:
                          'Guardado en el teléfono, pendiente de sincronizar',
                      child: Icon(
                        Icons.schedule,
                        size: 26,
                        color: colores.syncPending,
                      ),
                    ),
                ],
              ),
              if (priceText != null || photoCount > 0) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (priceText != null)
                      _Tag(icon: Icons.sell_rounded, text: priceText!),
                    if (photoCount > 0)
                      _Tag(
                        icon: Icons.photo_library_rounded,
                        text: photoCount == 1 ? '1 foto' : '$photoCount fotos',
                      ),
                  ],
                ),
              ],
              if (description != null && description!.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  description!,
                  style: texto.bodyMedium?.copyWith(
                    color: esquema.onSurfaceVariant,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (context, constraints) => Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    // Un pedido no se recomienda: no lleva Visto Bueno.
                    if (!isNeed)
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: constraints.maxWidth,
                        ),
                        child: VistoBuenoBadge(
                          count: endorsementsCount,
                          isEndorsed: isEndorsed,
                          onPressed: onEndorse,
                        ),
                      ),
                    if (isAvailableInEmergency)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: colores.urgencyHigh.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.health_and_safety,
                              size: 20,
                              color: colores.urgencyHigh,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'En emergencias',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: texto.labelMedium?.copyWith(
                                  color: colores.urgencyHigh,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colores = MiBarrioColors.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colores.pill,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colores.onPill),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: colores.onPill),
            ),
          ),
        ],
      ),
    );
  }
}

/// Insignia corta junto al rubro: "Vecino" / "Negocio", "Tuyo" o "Necesita".
class _Badge extends StatelessWidget {
  const _Badge({required this.text, this.strong = false, this.need = false});

  final String text;
  final bool strong;
  final bool need;

  @override
  Widget build(BuildContext context) {
    final colores = MiBarrioColors.of(context);
    final bg = strong
        ? Colors.white
        : need
        ? colores.pill
        : AppPalette.filterActiveBackground;
    final fg = strong
        ? colores.accentText
        : need
        ? colores.onPill
        : AppPalette.textPrimary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: fg,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
