import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_barrio_app/core/ui_kit/app_theme.dart';
import 'package:mi_barrio_app/features/onboarding_tutorial/presentation/screens/tutorial_gate.dart';
import 'package:mi_barrio_app/features/onboarding_tutorial/presentation/screens/tutorial_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  testWidgets('se ve solo la primera vez por cuenta', (tester) async {
    SharedPreferences.setMockInitialValues({});
    const child = Text('Pestañas de la app');

    await tester.pumpWidget(app(const TutorialGate(userId: 'vecina-1', child: child)));
    await tester.pumpAndSettle();
    expect(find.byType(TutorialScreen), findsOneWidget);
    await tester.tap(find.byKey(TutorialScreen.skipKey));
    await tester.pumpAndSettle();
    expect(find.text('Pestañas de la app'), findsOneWidget);

    // Reabrir la app con la misma cuenta: ya no aparece.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app(const TutorialGate(userId: 'vecina-1', child: child)));
    await tester.pumpAndSettle();
    expect(find.byType(TutorialScreen), findsNothing);
    expect(find.text('Pestañas de la app'), findsOneWidget);

    // Otra cuenta en el mismo teléfono sí lo ve.
    await tester.pumpWidget(app(const TutorialGate(userId: 'vecino-2', child: child)));
    await tester.pumpAndSettle();
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
