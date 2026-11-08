import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Si el teléfono tiene red o no.
enum ConnectionStatus { online, offline }

/// Indica si el teléfono TIENE una red (Wi-Fi, datos, etc.).
///
/// Es solo una pista: tener red no garantiza llegar al servidor, y el sistema
/// a veces no avisa un cambio (app en segundo plano, VPN, anclaje USB). Por
/// eso [refresh] vuelve a preguntar y la sincronización lo usa antes de
/// rendirse con "Modo offline".
class ConnectivityMonitor {
  ConnectivityMonitor._();
  static final ConnectivityMonitor instance = ConnectivityMonitor._();

  final Connectivity _connectivity = Connectivity();
  final StreamController<ConnectionStatus> _controller =
      StreamController<ConnectionStatus>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _sub;
  ConnectionStatus _current = ConnectionStatus.offline;

  ConnectionStatus get current => _current;
  Stream<ConnectionStatus> get stream => _controller.stream;

  /// Llamar una vez al inicio de la app (en main()).
  Future<void> start() async {
    await refresh();
    _controller.add(_current); // estado inicial
    _sub ??= _connectivity.onConnectivityChanged.listen(
      (results) => _set(toStatus(results)),
      // Si el sistema falla al avisar, no quedarse "offline" para siempre.
      onError: (Object _) => _set(ConnectionStatus.online),
    );
  }

  /// Vuelve a preguntar al sistema (al volver a la app o antes de decir
  /// "offline"). Si el sistema no responde, se asume que hay red y que la
  /// petición HTTP decida.
  Future<ConnectionStatus> refresh() async {
    try {
      _set(toStatus(await _connectivity.checkConnectivity()));
    } catch (_) {
      _set(ConnectionStatus.online);
    }
    return _current;
  }

  void _set(ConnectionStatus status) {
    if (status == _current) return; // solo emite cuando cambia
    _current = status;
    _controller.add(status);
  }

  /// En connectivity_plus 6.x los eventos son una lista de interfaces activas.
  /// Solo es "offline" si no hay NINGUNA (lista vacía o solo `none`): una VPN,
  /// un anclaje (`other`) o bluetooth también pueden llevar internet.
  @visibleForTesting
  static ConnectionStatus toStatus(List<ConnectivityResult> results) {
    final sinRed =
        results.isEmpty || results.every((r) => r == ConnectivityResult.none);
    return sinRed ? ConnectionStatus.offline : ConnectionStatus.online;
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }
}
