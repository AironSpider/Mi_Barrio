import 'package:flutter/material.dart';

import 'app_theme.dart';

enum SyncChipStatus { pending, synced, failed }

class SyncStatusChip extends StatelessWidget {
  const SyncStatusChip({super.key, required this.status, this.compact = false});

  factory SyncStatusChip.fromPending(
    bool isPending, {
    Key? key,
    bool compact = false,
  }) {
    return SyncStatusChip(
      key: key,
      status: isPending ? SyncChipStatus.pending : SyncChipStatus.synced,
      compact: compact,
    );
  }

  final SyncChipStatus status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final (icono, texto, frente, fondo) = switch (status) {
      SyncChipStatus.pending => (
        Icons.schedule_rounded,
        'Pendiente',
        AppPalette.pendingText,
        AppPalette.pendingBackground,
      ),
      SyncChipStatus.synced => (
        Icons.check_circle_rounded,
        'Sincronizado',
        AppPalette.syncSynced,
        AppPalette.syncedBackground,
      ),
      SyncChipStatus.failed => (
        Icons.error_outline_rounded,
        'Sin enviar',
        AppPalette.syncFailed,
        AppPalette.failedBackground,
      ),
    };

    final descripcion = switch (status) {
      SyncChipStatus.pending =>
        'Guardado en el teléfono, pendiente de sincronizar',
      SyncChipStatus.synced => 'Sincronizado con Mi Barrio',
      SyncChipStatus.failed => 'No se pudo enviar, se reintentará',
    };

    return Semantics(
      label: descripcion,
      excludeSemantics: true,
      child: Tooltip(
        message: descripcion,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 12,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: fondo,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icono, size: 20, color: frente),
              if (!compact) ...[
                const SizedBox(width: 6),
                Text(
                  texto,
                  style: Theme.of(context).textTheme.labelMedium
                      ?.copyWith(color: frente, fontWeight: FontWeight.w700),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
