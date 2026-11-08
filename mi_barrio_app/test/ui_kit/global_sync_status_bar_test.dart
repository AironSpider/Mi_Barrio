import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_barrio_app/core/sync_manager/sync_coordinator.dart';
import 'package:mi_barrio_app/core/ui_kit/app_theme.dart';
import 'package:mi_barrio_app/core/ui_kit/global_sync_status_bar.dart';
import 'package:mi_barrio_app/core/ui_kit/main_navigation_shell.dart';
import 'package:mi_barrio_app/features/auth_barrio/presentation/providers/auth_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _bar(
  ValueNotifier<SyncPhase> phase, {
  double scale = 1,
  ValueNotifier<Duration?>? retry,
  ValueNotifier<DateTime?>? success,
}) {
  return MaterialApp(
    theme: AppTheme.day(),
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(360, 640),
        textScaler: TextScaler.linear(scale),
      ),
      child: Scaffold(
        body: GlobalSyncStatusBar(
          phase: phase,
          nextRetry: retry ?? ValueNotifier<Duration?>(null),
          lastSuccess: success ?? ValueNotifier<DateTime?>(DateTime(2026)),
        ),
      ),
    ),
  );
}

void main() {
  const casos = {
    SyncPhase.offline: (
      GlobalSyncStatusBar.offlineText,
      Icons.cloud_off_rounded,
    ),
    SyncPhase.idle: (GlobalSyncStatusBar.syncedText, Icons.cloud_done_rounded),
    SyncPhase.syncing: (GlobalSyncStatusBar.syncingText, Icons.sync_rounded),
    SyncPhase.error: (
      GlobalSyncStatusBar.errorText,
      Icons.sync_problem_rounded,
    ),
  };

  for (final MapEntry(key: fase, value: (texto, icono)) in casos.entries) {
    testWidgets('fase $fase muestra ícono + texto y lo anuncia', (tester) async {
      final handle = tester.ensureSemantics();
      final phase = ValueNotifier(fase);
      await tester.pumpWidget(_bar(phase));

      expect(find.text(texto), findsOneWidget);
      expect(find.byIcon(icono), findsOneWidget);
      expect(find.bySemanticsLabel(texto), findsOneWidget);
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });

    testWidgets('fase $fase con texto al 200 % no desborda', (tester) async {
      final phase = ValueNotifier(fase);
      await tester.pumpWidget(_bar(phase, scale: 2));
      expect(find.text(texto), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('antes de la primera sincronización dice "Conectando", no "Sincronizado"', (
    tester,
  ) async {
    final phase = ValueNotifier(SyncPhase.idle);
    final success = ValueNotifier<DateTime?>(null);
    await tester.pumpWidget(_bar(phase, success: success));
    expect(find.text(GlobalSyncStatusBar.connectingText), findsOneWidget);
    expect(find.text(GlobalSyncStatusBar.syncedText), findsNothing);

    success.value = DateTime.now();
    await tester.pumpAndSettle();
    expect(find.text(GlobalSyncStatusBar.syncedText), findsOneWidget);
  });

  testWidgets('si el servidor falla muestra "Reintentando en N s"', (tester) async {
    final handle = tester.ensureSemantics();
    final phase = ValueNotifier(SyncPhase.error);
    final retry = ValueNotifier<Duration?>(const Duration(seconds: 4));
    await tester.pumpWidget(_bar(phase, retry: retry));
    final texto = GlobalSyncStatusBar.retryText(const Duration(seconds: 4));
    expect(find.text(texto), findsOneWidget);
    expect(find.bySemanticsLabel(texto), findsOneWidget);
    await expectLater(tester, meetsGuideline(textContrastGuideline));

    // Se agotan los reintentos rápidos: vuelve al mensaje de error normal.
    retry.value = null;
    await tester.pumpAndSettle();
    expect(find.text(GlobalSyncStatusBar.errorText), findsOneWidget);
    handle.dispose();
  });

  testWidgets('reintento con texto al 200 % no desborda', (tester) async {
    await tester.pumpWidget(_bar(
      ValueNotifier(SyncPhase.error),
      scale: 2,
      retry: ValueNotifier<Duration?>(const Duration(seconds: 16)),
    ));
    expect(tester.takeException(), isNull);
  });

  testWidgets('cambia de "Modo offline" a "Sincronizado" al volver la señal', (
    tester,
  ) async {
    final phase = ValueNotifier(SyncPhase.offline);
    await tester.pumpWidget(_bar(phase));
    expect(find.text(GlobalSyncStatusBar.offlineText), findsOneWidget);

    phase.value = SyncPhase.idle;
    await tester.pumpAndSettle();
    expect(find.text(GlobalSyncStatusBar.syncedText), findsOneWidget);
    expect(find.text(GlobalSyncStatusBar.offlineText), findsNothing);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('visible en las 4 pestañas (texto x$scale)', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final phase = ValueNotifier(SyncPhase.offline);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(
              (ref) => AuthNotifier(
                ref.read(authRepositoryProvider),
                initialState: const AuthState.unauthenticated(),
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.day(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: MainNavigationShell(
              isEmergencyMode: false,
              syncPhase: phase,
            ),
          ),
        ),
      );
      await tester.pump();

      for (final id in ['servicios', 'apoyo', 'mapa', 'tu']) {
        await tester.tap(find.byKey(ValueKey('nav_$id')));
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          find.byKey(GlobalSyncStatusBar.barKey),
          findsOneWidget,
          reason: 'pestaña $id',
        );
        expect(find.text(GlobalSyncStatusBar.offlineText), findsOneWidget);
      }
      // Los errores de desborde de las pantallas no son de esta barra.
      tester.takeException();
    });
  }
}
