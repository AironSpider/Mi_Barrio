import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_barrio_app/core/ui_kit/app_theme.dart';
import 'package:mi_barrio_app/core/ui_kit/main_navigation_shell.dart';
import 'package:mi_barrio_app/core/ui_kit/quick_publish_fab.dart';
import 'package:mi_barrio_app/core/barrio_context/emergency_mode_provider.dart';
import 'package:mi_barrio_app/features/proximity_services/presentation/screens/services_directory_screen.dart';
import 'package:mi_barrio_app/main.dart';

void main() {
  testWidgets('arranca en modo día a día con 4 pestañas y botón Publicar', (
    tester,
  ) async {
    await tester.pumpWidget(const MiBarrioApp());

    expect(find.text('Mi Barrio'), findsOneWidget);
    expect(find.byType(NavigationDestination), findsNWidgets(4));
    for (final label in ['Servicios', 'Apoyo', 'Mapa', 'Tú']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Publicar'), findsOneWidget);
    expect(find.byType(ServicesDirectoryScreen), findsOneWidget);
    expect(find.byKey(MainNavigationShell.emergencyBannerKey), findsNothing);
  });

  testWidgets('las pestañas cambian el contenido', (tester) async {
    await tester.pumpWidget(const MiBarrioApp());

    await tester.tap(find.text('Apoyo'));
    await tester.pumpAndSettle();
    expect(find.text('Muro solidario'), findsOneWidget);

    await tester.tap(find.text('Mapa'));
    await tester.pumpAndSettle();
    expect(find.text('Mapa de ayuda'), findsOneWidget);
  });

  testWidgets('el modo emergencia conserva las pestañas y aplica el tema', (
    tester,
  ) async {
    await tester.pumpWidget(const MiBarrioApp());

    await tester.ensureVisible(
      find.byKey(MainNavigationShell.emergencyPreviewSwitchKey),
    );
    await tester.tap(find.byKey(MainNavigationShell.emergencyPreviewSwitchKey));
    await tester.pumpAndSettle();

    expect(find.byKey(MainNavigationShell.emergencyBannerKey), findsOneWidget);
    expect(find.byType(NavigationDestination), findsNWidgets(4));
    for (final label in ['Servicios', 'Apoyo', 'Mapa', 'Tú']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Pedir ayuda'), findsOneWidget);

    final context = tester.element(find.byType(MainNavigationShell));
    expect(Theme.of(context).colorScheme.primary, AppPalette.emergencyPrimary);

    // Y vuelve al modo normal.
    await tester.tap(find.byKey(MainNavigationShell.emergencyPreviewSwitchKey));
    await tester.pumpAndSettle();
    expect(find.text('Publicar'), findsOneWidget);
    expect(find.byKey(MainNavigationShell.emergencyBannerKey), findsNothing);
  });

  testWidgets('el estado de emergencia del barrio actualiza la app', (
    tester,
  ) async {
    final emergency = EmergencyModeProvider.instance;
    await tester.pumpWidget(const MiBarrioApp());

    emergency.setTenantFlag(true);
    await tester.pumpAndSettle();
    expect(find.byKey(MainNavigationShell.emergencyBannerKey), findsOneWidget);

    emergency.setTenantFlag(false);
    await tester.pumpAndSettle();
    expect(find.byKey(MainNavigationShell.emergencyBannerKey), findsNothing);
  });

  testWidgets('el botón (+) abre el modal de publicación rápida', (
    tester,
  ) async {
    await tester.pumpWidget(const MiBarrioApp());

    await tester.tap(find.byKey(QuickPublishFab.fabKey));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
  });

  testWidgets('sin onPublish, el botón (+) avisa en lugar de fallar', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.day(),
        home: const MainNavigationShell(isEmergencyMode: false),
      ),
    );

    await tester.tap(find.byKey(QuickPublishFab.fabKey));
    await tester.pump();
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('el botón (+) llama a onPublish cuando está conectado', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.day(),
        home: MainNavigationShell(
          isEmergencyMode: false,
          onPublish: () => calls++,
        ),
      ),
    );

    await tester.tap(find.byKey(QuickPublishFab.fabKey));
    await tester.pump();
    expect(calls, 1);
  });

  for (final emergency in [false, true]) {
    testWidgets('accesibilidad (${emergency ? 'emergencia' : 'día a día'}): '
        'áreas táctiles, etiquetas y contraste', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(MiBarrioApp(initialEmergencyMode: emergency));
      await tester.pumpAndSettle();

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });
  }

  testWidgets('soporta texto grande (escala 2x) sin desbordes', (tester) async {
    // Teléfono típico (360x780 dp) con el texto del sistema al 200%.
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(const MiBarrioApp(initialEmergencyMode: true));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
