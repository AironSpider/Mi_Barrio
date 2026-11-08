import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_barrio_app/core/ui_kit/app_theme.dart';
import 'package:mi_barrio_app/features/auth_barrio/presentation/providers/auth_provider.dart';
import 'package:mi_barrio_app/features/auth_barrio/presentation/screens/register_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> open(WidgetTester tester, NeighborhoodLookup lookup) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authProvider.overrideWith((ref) => AuthNotifier(
              ref.read(authRepositoryProvider),
              initialState: const AuthState.unauthenticated(),
            )),
      ],
      child: MaterialApp(theme: AppTheme.day(), home: RegisterScreen(lookupNeighborhood: lookup)),
    ));
  }

  Future<void> typeCode(WidgetTester tester, String code) async {
    await tester.enterText(find.widgetWithText(TextFormField, 'Código de tu barrio'), code);
    await tester.pump(const Duration(milliseconds: 700)); // espera del debounce
    await tester.pump();
  }

  testWidgets('el código va primero y confirma "Te vas a unir a: …"', (tester) async {
    final asked = <String>[];
    await open(tester, (code) async {
      asked.add(code);
      return code == 'BARRIO-01' ? 'Junta Vecinal Demo (Piura)' : null;
    });
    final codeY = tester.getTopLeft(find.widgetWithText(TextFormField, 'Código de tu barrio')).dy;
    final nameY = tester.getTopLeft(find.widgetWithText(TextFormField, 'Nombre completo')).dy;
    expect(codeY, lessThan(nameY));

    await typeCode(tester, 'BARRIO-01');
    expect(find.text('Te vas a unir a: Junta Vecinal Demo (Piura)'), findsOneWidget);
    expect(asked, ['BARRIO-01'], reason: 'una sola consulta tras dejar de escribir');
  });

  testWidgets('un código que no existe lo avisa', (tester) async {
    await open(tester, (_) async => null);
    await typeCode(tester, 'NO-EXISTE');
    expect(find.textContaining('No encontramos un barrio con ese código'), findsOneWidget);
  });

  testWidgets('sin conexión no bloquea el registro', (tester) async {
    await open(tester, (_) async => throw Exception('sin red'));
    await typeCode(tester, 'BARRIO-01');
    expect(find.textContaining('No pudimos verificar el código ahora'), findsOneWidget);
  });
}
