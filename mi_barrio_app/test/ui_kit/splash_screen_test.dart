import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_barrio_app/core/ui_kit/splash_screen.dart';
import 'package:mi_barrio_app/features/auth_barrio/presentation/providers/auth_provider.dart';

void main() {
  testWidgets('la bienvenida avisa si la conexión está lenta', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SplashScreen()));
    expect(find.text('Abriendo tu barrio…'), findsOneWidget);
    expect(find.byKey(SplashScreen.slowKey), findsNothing);

    await tester.pump(SplashScreen.slowAfter);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(SplashScreen.slowKey), findsOneWidget);
  });

  test('solo el "cargando" de abrir la app es de restauración', () {
    expect(const AuthState.restoring().restoring, isTrue);
    expect(const AuthState.restoring().status, AuthStatus.loading);
    // Ingresar o registrarse no cambia la pantalla de ingreso por la bienvenida.
    expect(const AuthState.loading().restoring, isFalse);
  });

  testWidgets('la bienvenida cumple contraste y anuncia el estado', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(const MaterialApp(home: SplashScreen()));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    expect(find.bySemanticsLabel('Abriendo tu barrio…'), findsOneWidget);
    await tester.pump(SplashScreen.slowAfter);
    await tester.pump(const Duration(milliseconds: 300));
    handle.dispose();
  });
}
