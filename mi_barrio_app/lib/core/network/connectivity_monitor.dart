import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

enum ConnectionStatus { online, offline }

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
    _current = _toStatus(await _connectivity.checkConnectivity());
    _controller.add(_current); // estado inicial
    _sub ??= _connectivity.onConnectivityChanged.listen((results) {
      final status = _toStatus(results);
      if (status != _current) { // solo emite cuando cambia
        _current = status;
        _controller.add(status);
      }
    });
  }

  // En connectivity_plus 6.x los eventos son una lista de interfaces activas.
  ConnectionStatus _toStatus(List<ConnectivityResult> results) {
    final online = results.any((r) =>
        r == ConnectivityResult.wifi ||
        r == ConnectivityResult.mobile ||
        r == ConnectivityResult.ethernet);
    return online ? ConnectionStatus.online : ConnectionStatus.offline;
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }
}