import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_barrio_app/core/network/connectivity_monitor.dart';
import 'package:mi_barrio_app/core/sync_manager/sync_coordinator.dart';
import 'package:mi_barrio_app/core/sync_manager/sync_worker.dart';

/// Bug de conectividad: la app decía "Modo offline" con internet, o no salía
/// de ese estado al volver la señal.
class _CountingWorker extends SyncWorker {
  _CountingWorker({this.push = const PushResult(success: true)})
    : super(baseUrl: 'http://test');
  PushResult push;
  int runs = 0;

  @override
  Future<PushResult> pushLocalChanges(String tenantId) async {
    runs++;
    return push;
  }

  @override
  Future<PullResult> pullRemoteChanges(String tenantId) async =>
      const PullResult(success: true);
}

void main() {
  const tenant = 'a1b2c3d4-e5f6-4a8b-9c0d-1e2f3a4b5c6d';
  final sync = SyncCoordinator.instance;

  tearDown(() => sync.stop());

  group('Qué cuenta como "hay red"', () {
    test('sin interfaces o solo none → offline', () {
      expect(ConnectivityMonitor.toStatus([]), ConnectionStatus.offline);
      expect(
        ConnectivityMonitor.toStatus([ConnectivityResult.none]),
        ConnectionStatus.offline,
      );
    });

    test('VPN, anclaje (other) y bluetooth también son red', () {
      for (final r in [
        ConnectivityResult.wifi,
        ConnectivityResult.mobile,
        ConnectivityResult.ethernet,
        ConnectivityResult.vpn,
        ConnectivityResult.other,
        ConnectivityResult.bluetooth,
      ]) {
        expect(
          ConnectivityMonitor.toStatus([r]),
          ConnectionStatus.online,
          reason: '$r',
        );
      }
    });
  });

  group('Segunda opinión antes de "Modo offline"', () {
    test(
      'si se perdió el aviso de "volvió internet", igual sincroniza',
      () async {
        final worker = _CountingWorker();
        final connection = StreamController<ConnectionStatus>.broadcast();
        addTearDown(connection.close);
        await sync.start(
          worker: worker,
          connectionChanges: connection.stream,
          isOnline: () => false, // el monitor se quedó en "offline"
          recheckOnline: () async => true, // pero el sistema ya tiene red
          tenantId: () => tenant,
          interval: const Duration(hours: 1),
          syncImmediately: false,
        );

        await sync.syncNow();

        expect(worker.runs, 1, reason: 'antes: nunca intentaba sincronizar');
        expect(sync.phase.value, SyncPhase.idle);
      },
    );

    test('sin red de verdad: Modo offline y no llama al servidor', () async {
      final worker = _CountingWorker();
      final connection = StreamController<ConnectionStatus>.broadcast();
      addTearDown(connection.close);
      await sync.start(
        worker: worker,
        connectionChanges: connection.stream,
        isOnline: () => false,
        recheckOnline: () async => false,
        tenantId: () => tenant,
        interval: const Duration(hours: 1),
        syncImmediately: false,
      );

      await sync.syncNow();

      expect(worker.runs, 0);
      expect(sync.phase.value, SyncPhase.offline);
    });

    test(
      'se fue la señal en plena sincronización → offline, no error rojo',
      () async {
        var hayRed = true;
        final worker = _CountingWorker(
          push: const PushResult(
            success: false,
            message: 'SocketException: Failed host lookup',
            retryable: true,
          ),
        );
        final connection = StreamController<ConnectionStatus>.broadcast();
        addTearDown(connection.close);
        await sync.start(
          worker: worker,
          connectionChanges: connection.stream,
          isOnline: () => true,
          recheckOnline: () async => hayRed,
          tenantId: () => tenant,
          interval: const Duration(hours: 1),
          syncImmediately: false,
        );

        hayRed = false; // modo avión mientras subía
        await sync.syncNow();

        expect(sync.phase.value, SyncPhase.offline);
        expect(sync.nextRetry.value, isNull, reason: 'sin red no se reintenta');
      },
    );
  });

  test('dos start() seguidos no duplican la sincronización', () async {
    final worker = _CountingWorker();
    final connection = StreamController<ConnectionStatus>.broadcast();
    addTearDown(connection.close);
    Future<void> start() => sync.start(
      worker: worker,
      connectionChanges: connection.stream,
      isOnline: () => true,
      tenantId: () => tenant,
      interval: const Duration(hours: 1),
      syncImmediately: false,
    );

    // Login y refresco del perfil casi a la vez (sin await entre ellos).
    final a = start();
    final b = start();
    await Future.wait([a, b]);

    connection.add(ConnectionStatus.online);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(
      worker.runs,
      1,
      reason: 'antes: 2 suscripciones → 2 rondas por evento',
    );
  });
}
