import 'dart:async';

import 'package:flutter/foundation.dart';

import '../barrio_context/tenant_session.dart';
import '../database_sqlite/sync_outbox_dao.dart';
import '../network/api_client.dart';
import '../network/connectivity_monitor.dart';
import 'sync_worker.dart';

/// Estado visible de la sincronización (para la barra "Modo offline / Sincronizado").
enum SyncPhase { idle, syncing, offline, error }

/// Orquesta cuándo sincronizar (Checkpoint 1):
/// 1. Al abrir la app.
/// 2. Cuando vuelve internet.
/// 3. Poco después de cada publicación nueva (si hay red).
/// 4. Cada [interval] como respaldo.
///
/// Nunca corre dos sincronizaciones a la vez; si llega un pedido durante una,
/// se hace una ronda más al terminar.
class SyncCoordinator {
  SyncCoordinator._();
  static final SyncCoordinator instance = SyncCoordinator._();

  /// Estado actual, para que la UI lo muestre (Sprint 10).
  final ValueNotifier<SyncPhase> phase = ValueNotifier(SyncPhase.idle);

  /// Fecha de la última sincronización exitosa (push + pull).
  final ValueNotifier<DateTime?> lastSuccess = ValueNotifier(null);
  final ValueNotifier<String?> lastError = ValueNotifier(null);

  SyncWorker? _worker;
  bool Function() _isOnline = () => true;
  String Function() _tenantId = () => TenantSession.instance.tenantId;

  StreamSubscription<ConnectionStatus>? _connectionSub;
  StreamSubscription<String>? _queueSub;
  Timer? _periodic;
  Timer? _debounce;
  bool _running = false;
  bool _runAgain = false;

  bool get isRunning => _running;

  /// Llamar una vez en main(), después de `ConnectivityMonitor.instance.start()`.
  Future<void> start({
    SyncWorker? worker,
    Stream<ConnectionStatus>? connectionChanges,
    bool Function()? isOnline,
    String Function()? tenantId,
    Duration interval = const Duration(seconds: 60),
    bool syncImmediately = true,
  }) async {
    await stop();
    _worker = worker ?? SyncWorker(baseUrl: ApiConfig.baseUrl);
    lastError.value = null;
    _isOnline =
        isOnline ??
        () => ConnectivityMonitor.instance.current == ConnectionStatus.online;
    if (tenantId != null) _tenantId = tenantId;

    _connectionSub = (connectionChanges ?? ConnectivityMonitor.instance.stream)
        .listen((status) {
          if (status == ConnectionStatus.online) {
            syncNow();
          } else {
            phase.value = SyncPhase.offline;
          }
        });

    _queueSub = SyncOutboxDao.onQueued.listen((_) {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 400), syncNow);
    });

    _periodic = Timer.periodic(interval, (_) => syncNow());

    if (syncImmediately) unawaited(syncNow());
  }

  /// Sincroniza ahora (push y luego pull). Seguro de llamar muchas veces.
  Future<void> syncNow() async {
    final worker = _worker;
    if (worker == null) return;
    if (_running) {
      _runAgain = true;
      return;
    }
    _running = true;
    try {
      do {
        _runAgain = false;
        if (!_isOnline()) {
          phase.value = SyncPhase.offline;
          break;
        }
        phase.value = SyncPhase.syncing;
        final tenant = _tenantId();
        final push = await worker.pushLocalChanges(tenant);
        if (push.unauthorized) {
          phase.value = SyncPhase.error;
          lastError.value = push.message;
          break;
        }
        final pull = await worker.pullRemoteChanges(tenant);
        if (pull.unauthorized) {
          phase.value = SyncPhase.error;
          lastError.value = pull.message;
          break;
        }
        if (push.success && pull.success) {
          phase.value = SyncPhase.idle;
          lastError.value = null;
          lastSuccess.value = DateTime.now();
        } else {
          phase.value = SyncPhase.error;
          lastError.value = push.success ? pull.message : push.message;
          if (kDebugMode) {
            debugPrint(
              '[Sync] push: ${push.message ?? 'ok'} | pull: ${pull.message ?? 'ok'}',
            );
          }
        }
      } while (_runAgain);
    } finally {
      _running = false;
    }
  }

  /// Ajusta la frecuencia (Sprint 8: 15 s en emergencia, 60 s en modo normal).
  void setInterval(Duration interval) {
    _periodic?.cancel();
    _periodic = Timer.periodic(interval, (_) => syncNow());
  }

  Future<void> stop() async {
    await _connectionSub?.cancel();
    await _queueSub?.cancel();
    _periodic?.cancel();
    _debounce?.cancel();
    _connectionSub = null;
    _queueSub = null;
    _periodic = null;
    _debounce = null;
    while (_running) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    _worker = null;
  }
}
