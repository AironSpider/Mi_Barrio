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
///
/// Reintentos (Sprint 12): si el SERVIDOR falla (5xx, sin respuesta, tiempo
/// agotado) estando con red, se reintenta a los 2, 4, 8 y 16 s. Después sigue
/// el ritmo normal ([interval]). Cualquier sincronización exitosa reinicia la
/// cuenta. No se reintenta sin red (lo hace la vuelta de internet), con la
/// sesión vencida (401) ni por datos rechazados (reintentar no los arregla).
class SyncCoordinator {
  SyncCoordinator._();
  static final SyncCoordinator instance = SyncCoordinator._();

  /// Esperas entre reintentos: 2, 4, 8 y 16 segundos.
  static const defaultRetryDelays = [
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 16),
  ];

  /// Estado actual, para que la UI lo muestre (Sprint 10).
  final ValueNotifier<SyncPhase> phase = ValueNotifier(SyncPhase.idle);

  /// Fecha de la última sincronización exitosa (push + pull).
  final ValueNotifier<DateTime?> lastSuccess = ValueNotifier(null);
  final ValueNotifier<String?> lastError = ValueNotifier(null);

  /// Espera del próximo reintento programado (null = ninguno). Para la UI:
  /// "Reintentando en 4 s…".
  final ValueNotifier<Duration?> nextRetry = ValueNotifier(null);

  List<Duration> _retryDelays = defaultRetryDelays;
  int _retryAttempt = 0;
  Timer? _retryTimer;

  /// Cuántos reintentos seguidos se programaron desde el último éxito.
  int get retryAttempt => _retryAttempt;

  SyncWorker? _worker;
  bool Function() _isOnline = () => true;

  /// Segunda opinión antes de decir "offline": vuelve a preguntar al sistema.
  /// Sin esto, si se perdía el aviso de "volvió internet", la app quedaba en
  /// "Modo offline" para siempre (ni el respaldo de 60 s lo arreglaba).
  Future<bool> Function() _recheckOnline = () async => true;

  /// Cada start()/stop() sube este número. Si llega uno más nuevo mientras
  /// otro espera, el viejo no instala nada: dos start() seguidos (login +
  /// refresco del perfil) dejaban timers y suscripciones duplicados.
  int _generation = 0;
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
    Future<bool> Function()? recheckOnline,
    String Function()? tenantId,
    Duration interval = const Duration(seconds: 60),
    bool syncImmediately = true,
    List<Duration> retryDelays = defaultRetryDelays,
  }) async {
    final generation = ++_generation;
    await _stop();
    if (generation != _generation) return; // lo reemplazó otro start()/stop()
    _worker = worker ?? SyncWorker(baseUrl: ApiConfig.baseUrl);
    _retryDelays = retryDelays;
    lastError.value = null;
    _isOnline =
        isOnline ??
        () => ConnectivityMonitor.instance.current == ConnectionStatus.online;
    // Con un isOnline de prueba, la segunda opinión es el mismo isOnline.
    _recheckOnline =
        recheckOnline ??
        (isOnline != null
            ? () async => isOnline()
            : () async =>
                  await ConnectivityMonitor.instance.refresh() ==
                  ConnectionStatus.online);
    if (tenantId != null) _tenantId = tenantId;

    _connectionSub = (connectionChanges ?? ConnectivityMonitor.instance.stream)
        .listen((status) {
          if (status == ConnectionStatus.online) {
            syncNow();
          } else {
            // Sin red no tiene sentido reintentar: al volver internet se
            // sincroniza solo y la cuenta empieza de nuevo en 2 s.
            _resetRetries();
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
    // Esta ronda reemplaza a cualquier reintento que estuviera esperando.
    _retryTimer?.cancel();
    _retryTimer = null;
    nextRetry.value = null;
    var outcome = _Outcome.success;
    try {
      do {
        _runAgain = false;
        if (!_isOnline() && !await _recheckOnline()) {
          phase.value = SyncPhase.offline;
          outcome = _Outcome.offline;
          break;
        }
        phase.value = SyncPhase.syncing;
        final tenant = _tenantId();
        final push = await worker.pushLocalChanges(tenant);
        if (push.unauthorized) {
          phase.value = SyncPhase.error;
          lastError.value = push.message;
          outcome = _Outcome.stop;
          break;
        }
        final pull = await worker.pullRemoteChanges(tenant);
        if (pull.unauthorized) {
          phase.value = SyncPhase.error;
          lastError.value = pull.message;
          outcome = _Outcome.stop;
          break;
        }
        if (push.success && pull.success) {
          phase.value = SyncPhase.idle;
          lastError.value = null;
          lastSuccess.value = DateTime.now();
          outcome = _Outcome.success;
        } else {
          phase.value = SyncPhase.error;
          lastError.value = push.success ? pull.message : push.message;
          final transient =
              (!push.success && push.retryable) ||
              (!pull.success && pull.retryable);
          outcome = transient ? _Outcome.retry : _Outcome.stop;
          // Se fue la señal en plena sincronización (modo avión): es
          // "Modo offline", no un error rojo con reintentos.
          if (transient && !await _recheckOnline()) {
            phase.value = SyncPhase.offline;
            outcome = _Outcome.offline;
          }
          if (kDebugMode) {
            debugPrint(
              '[Sync] push: ${push.message ?? 'ok'} | pull: ${pull.message ?? 'ok'}',
            );
          }
        }
      } while (_runAgain);
    } catch (e) {
      // Un error inesperado no debe dejar la sincronización trabada.
      phase.value = SyncPhase.error;
      lastError.value = e.toString();
      outcome = _Outcome.retry;
    } finally {
      _running = false;
    }
    _afterRound(outcome);
  }

  /// Falla temporal → próximo reintento; éxito, sin red o falla definitiva →
  /// se cancela lo programado y la cuenta vuelve a empezar en 2 s.
  void _afterRound(_Outcome outcome) =>
      outcome == _Outcome.retry ? _scheduleRetry() : _resetRetries();

  void _scheduleRetry() {
    if (_worker == null || _retryAttempt >= _retryDelays.length) {
      // Se agotaron los reintentos rápidos: sigue el ritmo normal ([interval]).
      nextRetry.value = null;
      return;
    }
    final wait = _retryDelays[_retryAttempt++];
    nextRetry.value = wait;
    _retryTimer = Timer(wait, () {
      _retryTimer = null;
      syncNow();
    });
  }

  void _resetRetries() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _retryAttempt = 0;
    nextRetry.value = null;
  }

  /// Ajusta la frecuencia (Sprint 8: 15 s en emergencia, 60 s en modo normal).
  void setInterval(Duration interval) {
    if (_worker == null) return; // detenido: start() fija el intervalo
    _periodic?.cancel();
    _periodic = Timer.periodic(interval, (_) => syncNow());
  }

  Future<void> stop() {
    _generation++;
    return _stop();
  }

  Future<void> _stop() async {
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
    _resetRetries(); // después de esperar: la ronda en curso ya no programa nada
  }
}

/// Cómo terminó una ronda de sincronización.
enum _Outcome { success, offline, retry, stop }
