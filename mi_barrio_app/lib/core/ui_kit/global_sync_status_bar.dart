import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../sync_manager/sync_coordinator.dart';
import 'app_theme.dart';

/// Barra de estado global (Sprint 12): se ve en todas las pestañas, debajo de
/// la barra superior. Siempre usa ícono + texto (nunca solo color) y el texto
/// puede ocupar varias líneas para que funcione con letra al 200 %.
class GlobalSyncStatusBar extends StatelessWidget {
  const GlobalSyncStatusBar({
    super.key,
    this.phase,
    this.nextRetry,
    this.lastSuccess,
  });

  /// Fuentes del estado. En la app son las del [SyncCoordinator];
  /// los tests pasan sus propios notifiers.
  final ValueListenable<SyncPhase>? phase;
  final ValueListenable<Duration?>? nextRetry;
  final ValueListenable<DateTime?>? lastSuccess;

  static const barKey = ValueKey('global_sync_status_bar');

  static const offlineText =
      'Modo offline · tus datos están guardados en el teléfono';
  static const syncedText = 'Sincronizado con Mi Barrio';
  static const syncingText = 'Sincronizando con Mi Barrio…';
  static const connectingText = 'Conectando con Mi Barrio…';
  static const errorText =
      'Sin conexión con el servidor · tus datos están guardados en el teléfono';

  static String retryText(Duration wait) =>
      'Reintentando en ${wait.inSeconds} s · tus datos están guardados en el teléfono';

  @override
  Widget build(BuildContext context) {
    final sync = SyncCoordinator.instance;
    final phaseL = phase ?? sync.phase;
    final retryL = nextRetry ?? sync.nextRetry;
    final successL = lastSuccess ?? sync.lastSuccess;

    return ListenableBuilder(
      listenable: Listenable.merge([phaseL, retryL, successL]),
      builder: (context, _) {
        final value = phaseL.value;
        final retry = retryL.value;
        final (estado, icono, texto, frente, fondo) = switch (value) {
          SyncPhase.offline => (
            'offline',
            Icons.cloud_off_rounded,
            offlineText,
            AppPalette.pendingText,
            AppPalette.pendingBackground,
          ),
          SyncPhase.error when retry != null => (
            'retry',
            Icons.sync_problem_rounded,
            retryText(retry),
            AppPalette.syncFailed,
            AppPalette.failedBackground,
          ),
          SyncPhase.error => (
            'error',
            Icons.sync_problem_rounded,
            errorText,
            AppPalette.syncFailed,
            AppPalette.failedBackground,
          ),
          SyncPhase.syncing => (
            'syncing',
            Icons.sync_rounded,
            syncingText,
            AppPalette.syncSynced,
            AppPalette.syncedBackground,
          ),
          // Aún no hubo ninguna sincronización: no decir "Sincronizado".
          SyncPhase.idle when successL.value == null => (
            'connecting',
            Icons.cloud_queue_rounded,
            connectingText,
            AppPalette.syncSynced,
            AppPalette.syncedBackground,
          ),
          SyncPhase.idle => (
            'synced',
            Icons.cloud_done_rounded,
            syncedText,
            AppPalette.syncSynced,
            AppPalette.syncedBackground,
          ),
        };

        return Semantics(
          key: barKey,
          container: true,
          liveRegion: true,
          label: texto,
          excludeSemantics: true,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: double.infinity,
            color: fondo,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Icon(icono, size: 20, color: frente),
                const SizedBox(width: 8),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Text(
                      texto,
                      key: ValueKey(estado),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: frente,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
