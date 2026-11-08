import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../sync_manager/sync_coordinator.dart';
import 'app_theme.dart';

/// Barra de estado global: en todas las pestañas, debajo de la barra superior.
///
/// Solo aparece cuando hay algo que contar: sin señal, error o reintento.
/// Cuando todo está bien no ocupa espacio; al resolverse un problema muestra
/// "Sincronizado" unos segundos ([recoveredDuration]) y se oculta.
/// Siempre usa ícono + texto (nunca solo color) y el texto puede ocupar varias
/// líneas para que funcione con letra al 200 %.
class GlobalSyncStatusBar extends StatefulWidget {
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

  /// Cuánto se ve "Sincronizado" después de resolverse un problema.
  static const recoveredDuration = Duration(seconds: 3);

  @override
  State<GlobalSyncStatusBar> createState() => _GlobalSyncStatusBarState();
}

class _GlobalSyncStatusBarState extends State<GlobalSyncStatusBar> {
  late ValueListenable<SyncPhase> _phase;
  bool _hadProblem = false;
  bool _showRecovered = false;
  Timer? _hideTimer;

  static bool _isProblem(SyncPhase p) => p == SyncPhase.offline || p == SyncPhase.error;

  @override
  void initState() {
    super.initState();
    _phase = widget.phase ?? SyncCoordinator.instance.phase;
    _hadProblem = _isProblem(_phase.value);
    _phase.addListener(_onPhase);
  }

  @override
  void didUpdateWidget(covariant GlobalSyncStatusBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.phase ?? SyncCoordinator.instance.phase;
    if (next != _phase) {
      _phase.removeListener(_onPhase);
      _phase = next..addListener(_onPhase);
    }
  }

  @override
  void dispose() {
    _phase.removeListener(_onPhase);
    _hideTimer?.cancel();
    super.dispose();
  }

  void _onPhase() {
    final problem = _isProblem(_phase.value);
    if (problem) {
      _hideTimer?.cancel();
      _hadProblem = true;
      _showRecovered = false;
    } else if (_hadProblem && _phase.value == SyncPhase.idle) {
      // El problema se resolvió: confirmarlo un momento y ocultar.
      _hadProblem = false;
      _showRecovered = true;
      _hideTimer?.cancel();
      _hideTimer = Timer(GlobalSyncStatusBar.recoveredDuration, () {
        if (mounted) setState(() => _showRecovered = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final sync = SyncCoordinator.instance;
    final phaseL = _phase;
    final retryL = widget.nextRetry ?? sync.nextRetry;
    final successL = widget.lastSuccess ?? sync.lastSuccess;

    return ListenableBuilder(
      listenable: Listenable.merge([phaseL, retryL, successL]),
      builder: (context, _) {
        final value = phaseL.value;
        final visible = _isProblem(value) || (_showRecovered && value == SyncPhase.idle);
        if (!visible) return const SizedBox(width: double.infinity);
        final retry = retryL.value;
        final (estado, icono, texto, frente, fondo) = switch (value) {
          SyncPhase.offline => (
            'offline',
            Icons.cloud_off_rounded,
            GlobalSyncStatusBar.offlineText,
            AppPalette.pendingText,
            AppPalette.pendingBackground,
          ),
          SyncPhase.error when retry != null => (
            'retry',
            Icons.sync_problem_rounded,
            GlobalSyncStatusBar.retryText(retry),
            AppPalette.syncFailed,
            AppPalette.failedBackground,
          ),
          SyncPhase.error => (
            'error',
            Icons.sync_problem_rounded,
            GlobalSyncStatusBar.errorText,
            AppPalette.syncFailed,
            AppPalette.failedBackground,
          ),
          SyncPhase.syncing => (
            'syncing',
            Icons.sync_rounded,
            GlobalSyncStatusBar.syncingText,
            AppPalette.syncSynced,
            AppPalette.syncedBackground,
          ),
          // Aún no hubo ninguna sincronización: no decir "Sincronizado".
          SyncPhase.idle when successL.value == null => (
            'connecting',
            Icons.cloud_queue_rounded,
            GlobalSyncStatusBar.connectingText,
            AppPalette.syncSynced,
            AppPalette.syncedBackground,
          ),
          SyncPhase.idle => (
            'synced',
            Icons.cloud_done_rounded,
            GlobalSyncStatusBar.syncedText,
            AppPalette.syncSynced,
            AppPalette.syncedBackground,
          ),
        };

        return Semantics(
          key: GlobalSyncStatusBar.barKey,
          container: true,
          liveRegion: true,
          label: texto,
          excludeSemantics: true,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: double.infinity,
            color: fondo,
            // "Todo bien" ocupa UNA línea fina (con letra grande se comía la
            // pantalla); los avisos importantes sí pueden usar varias líneas.
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: estado == 'synced' ? 4 : 8),
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
                      maxLines: estado == 'synced' ? 1 : null,
                      overflow: estado == 'synced' ? TextOverflow.ellipsis : null,
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
