import 'package:flutter/material.dart';

import '../../../../core/ui_kit/app_theme.dart';
import '../../../../core/ui_kit/sync_status_chip.dart';
import '../../../../core/ui_kit/location_map.dart';
import '../../../../shared/contact_launcher.dart';
import '../../domain/entities/vulnerable_report_entity.dart';

/// Tarjeta de un pedido de ayuda.
/// La urgencia se comunica con franja de color + ícono + texto (nunca solo color).
class HelpReportCard extends StatelessWidget {
  const HelpReportCard({
    super.key,
    required this.report,
    this.distanceLabel,
    this.isMine = false,
    this.onOfferHelp,
    this.busy = false,
  });

  final VulnerableReport report;
  final String? distanceLabel;
  final bool isMine;
  final VoidCallback? onOfferHelp;
  final bool busy;

  static const _typeIcons = {
    VulnerabilityType.atencionMedica: Icons.medical_services_rounded,
    VulnerabilityType.adultoMayorSolo: Icons.elderly_rounded,
    VulnerabilityType.movilidadReducida: Icons.accessible_rounded,
    VulnerabilityType.viviendaAfectada: Icons.house_siding_rounded,
    VulnerabilityType.faltaSuministros: Icons.water_drop_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    final esquema = Theme.of(context).colorScheme;
    final colores = MiBarrioColors.of(context);
    final (urgencyColor, urgencyIcon) = switch (report.urgencyLevel) {
      UrgencyLevel.critica => (colores.urgencyCritical, Icons.error_rounded),
      UrgencyLevel.alta => (colores.urgencyHigh, Icons.warning_rounded),
      _ => (colores.urgencyMedium, Icons.info_rounded),
    };
    final tipo = report.typeLabel;
    final estado = ReportStatus.labels[report.status] ?? report.status;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 6, color: urgencyColor),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _Badge(
                          icon: urgencyIcon,
                          label:
                              'Urgencia ${UrgencyLevel.labels[report.urgencyLevel] ?? ''}',
                          color: urgencyColor,
                        ),
                        if (distanceLabel != null)
                          _Badge(
                            icon: Icons.near_me_rounded,
                            label: distanceLabel!,
                            color: esquema.onSurfaceVariant,
                          ),
                        if (report.isPending)
                          SyncStatusChip.fromPending(true, compact: true),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(
                          _typeIcons[report.vulnerabilityType] ??
                              Icons.help_rounded,
                          color: esquema.onSurface,
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(tipo, style: texto.titleMedium)),
                      ],
                    ),
                    if (report.description.isNotEmpty &&
                        report.description != tipo) ...[
                      const SizedBox(height: 4),
                      Text(
                        report.description,
                        style: texto.bodyMedium?.copyWith(
                          color: esquema.onSurfaceVariant,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          isMine ? 'Tu pedido · $estado' : estado,
                          style: texto.labelLarge?.copyWith(
                            color: report.needsHelp
                                ? esquema.onSurface
                                : AppPalette.syncSynced,
                          ),
                        ),
                        OutlinedButton.icon(
                          key: ValueKey('report_location_${report.id}'),
                          onPressed: () => _showLocation(context),
                          icon: const Icon(Icons.location_on_outlined),
                          label: const Text('Ver ubicación'),
                        ),
                        if (!isMine && report.needsHelp && onOfferHelp != null)
                          FilledButton.icon(
                            key: ValueKey('offer_help_${report.id}'),
                            onPressed: busy ? null : onOfferHelp,
                            icon: const Icon(Icons.directions_run_rounded),
                            label: const Text('Voy en camino'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showLocation(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Ubicación de ${report.typeLabel}',
              style: Theme.of(sheetContext).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            LocationMap(
              lat: report.lat,
              lng: report.lng,
              label: 'Ubicación del pedido de ayuda',
              height: 240,
              icon: Icons.warning_rounded,
            ),
            const SizedBox(height: 8),
            SelectableText(
              'Latitud ${report.lat.toStringAsFixed(5)} · '
              'Longitud ${report.lng.toStringAsFixed(5)}',
              textAlign: TextAlign.center,
              style: Theme.of(sheetContext).textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () async {
                final opened = await ContactLauncher.directions(
                  report.lat,
                  report.lng,
                );
                if (!opened && sheetContext.mounted) {
                  ScaffoldMessenger.of(sheetContext).showSnackBar(
                    const SnackBar(
                      content: Text('No se pudo abrir la app de mapas.'),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.directions_rounded),
              label: const Text('Abrir en mapas'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}
