import 'package:flutter/material.dart';

import '../../../../core/ui_kit/app_theme.dart';
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
    this.onEndorse,
    this.onTap,
  });

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

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: esquema.outline.withValues(alpha: 0.35)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
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
                      color: esquema.primaryContainer,
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
                        Text(
                          categoryLabel,
                          style: texto.labelMedium?.copyWith(
                            color: esquema.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          title,
                          style: texto.titleMedium,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
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
              Row(
                children: [
                  VistoBuenoBadge(
                    count: endorsementsCount,
                    isEndorsed: isEndorsed,
                    onPressed: onEndorse,
                  ),
                  const Spacer(),
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
                          Text(
                            'En emergencias',
                            style: texto.labelMedium?.copyWith(
                              color: colores.urgencyHigh,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

