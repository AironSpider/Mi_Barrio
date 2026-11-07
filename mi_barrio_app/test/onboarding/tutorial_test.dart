import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_barrio_app/core/database_sqlite/sqlite_database.dart';
import 'package:mi_barrio_app/core/ui_kit/app_theme.dart';
import 'package:mi_barrio_app/features/onboarding_tutorial/presentation/screens/tutorial_gate.dart';
import 'package:mi_barrio_app/features/onboarding_tutorial/presentation/screens/tutorial_screen.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  Widget app(Widget home) => MaterialApp(theme: AppTheme.day(), home: home);

  testWidgets('recorre los 3 pasos y "Empezar" termina el tutorial', (tester) async {
    var finished = 0;
    await tester.pumpWidget(app(TutorialScreen(onFinished: () => finished++)));

    expect(find.text('Oficios de confianza'), findsOneWidget);
    expect(find.text('Paso 1 de 3'), findsOneWidget);
    await tester.tap(find.byKey(TutorialScreen.nextKey));
    await tester.pumpAndSettle();
    expect(find.text('Favores sin dinero'), findsOneWidget);
    expect(find.text('Paso 2 de 3'), findsOneWidget);
    await tester.tap(find.byKey(TutorialScreen.nextKey));
    await tester.pumpAndSettle();
    expect(find.text('Pedir ayuda en emergencia'), findsOneWidget);
    expect(find.text('Empezar'), findsOneWidget);
    expect(finished, 0);

    await tester.tap(find.byKey(TutorialScreen.nextKey));
    expect(finished, 1);
  });

  testWidgets('"Saltar" termina el tutorial desde cualquier paso', (tester) async {
    var finished = 0;
    await tester.pumpWidget(app(TutorialScreen(onFinished: () => finished++)));
    await tester.tap(find.byKey(TutorialScreen.skipKey));
    expect(finished, 1);
  });

  testWidgets('se ve solo la primera vez por cuenta (TutorialProgress)', (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await tester.runAsync(() => LocalDatabase.instance.resetForTesting(path: inMemoryDatabasePath));
    addTearDown(() => tester.runAsync(() => LocalDatabase.instance.close()));
    const tenant = 'a1b2c3d4-e5f6-4a8b-9c0d-1e2f3a4b5c6d';
    const vecina = '5f3a2c1b-1234-4abc-9def-0123456789ab';
    const vecino = '9a8b7c6d-5e4f-4a3b-8c2d-1e0f9a8b7c6d';
    const child = Text('Pestañas de la app');

    Future<void> openGate(String userId) async {
      await tester.pumpWidget(app(TutorialGate(key: ValueKey(userId), tenantId: tenant, userId: userId, child: child)));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pumpAndSettle();
    }

    await openGate(vecina);
    expect(find.byType(TutorialScreen), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(TutorialScreen.skipKey));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(find.text('Pestañas de la app'), findsOneWidget);

    // Reabrir la app con la misma cuenta: ya no aparece.
    await tester.pumpWidget(const SizedBox());
    await openGate(vecina);
    expect(find.byType(TutorialScreen), findsNothing);
    expect(find.text('Pestañas de la app'), findsOneWidget);

    // Otra cuenta en el mismo teléfono sí lo ve.
    await openGate(vecino);
    expect(find.byType(TutorialScreen), findsOneWidget);
  });

  testWidgets('accesible: áreas táctiles, etiquetas, contraste y texto al 200 %', (tester) async {
    final handle = tester.ensureSemantics();
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await tester.pumpWidget(app(TutorialScreen(onFinished: () {})));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });
}
