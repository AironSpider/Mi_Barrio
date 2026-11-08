import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_barrio_app/core/ui_kit/app_theme.dart';
import 'package:mi_barrio_app/features/auth_barrio/data/models/user_model.dart';
import 'package:mi_barrio_app/features/auth_barrio/domain/entities/user_entity.dart';
import 'package:mi_barrio_app/features/auth_barrio/domain/repositories/auth_repository.dart';
import 'package:mi_barrio_app/features/auth_barrio/presentation/providers/auth_provider.dart';
import 'package:mi_barrio_app/features/auth_barrio/presentation/screens/login_screen.dart';

/// Repositorio falso: registra los intentos y falla con [error] si se define.
class _FakeAuthRepository implements AuthRepository {
  final logins = <(String, String)>[];
  Object? error;

  @override
  Future<UserEntity> login({
    required String email,
    required String password,
  }) async {
    logins.add((email, password));
    if (error != null) throw error!;
    return UserModel.fromJson({
      'id': 'user-1',
      'tenant_id': 'tenant-1',
      'full_name': 'Rosa Vecina',
      'role': 'VECINO',
      'access_token': 'token-1',
      'tenant': const <String, dynamic>{},
    });
  }

  @override
  Future<UserEntity> register({
    required String fullName,
    required String email,
    required String password,
    required UserRole role,
    required String joinCode,
  }) async => throw UnimplementedError();

  @override
  Future<UserEntity?> restoreSession() async => null;

  @override
  Future<NeighborhoodProvisionEntity> createNeighborhood({
    required String neighborhoodName,
    String? existingJoinCode,
    required String adminFullName,
    required String adminEmail,
    required String adminPassword,
    required double centerLat,
    required double centerLng,
  }) async => throw UnimplementedError();

  @override
  Future<void> logout() async {}

  @override
  Future<void> purgeLocalUserData({
    required String tenantId,
    required String userId,
  }) async {}

  @override
  Future<void> keepPendingDataFor({
    required String tenantId,
    required String userId,
  }) async {}

  @override
  Future<void> reconcilePendingData(UserEntity user) async {}
}

void main() {
  late _FakeAuthRepository repo;

  setUp(() => repo = _FakeAuthRepository());

  Future<void> open(
    WidgetTester tester, {
    AuthState initial = const AuthState.unauthenticated(),
    double textScale = 1,
    Size size = const Size(412, 915),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith(
            (ref) => AuthNotifier(repo, initialState: initial),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.day(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const LoginScreen(),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(LoginScreen.submitKey));
    await tester.tap(find.byKey(LoginScreen.submitKey));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('muestra la marca, el lema y los dos campos', (tester) async {
    await open(tester);
    expect(find.text('Mi Barrio'), findsOneWidget);
    expect(
      find.text('Tu barrio conectado, aunque no haya señal.'),
      findsOneWidget,
    );
    expect(find.text('Ingresa a tu barrio'), findsOneWidget);
    expect(find.byKey(LoginScreen.emailFieldKey), findsOneWidget);
    expect(find.byKey(LoginScreen.passwordFieldKey), findsOneWidget);
    expect(find.text('Ingresar'), findsOneWidget);
    expect(find.text('Crear una cuenta'), findsOneWidget);
  });

  testWidgets('con los campos vacíos explica qué falta y no intenta ingresar', (
    tester,
  ) async {
    await open(tester);
    await submit(tester);
    expect(find.text('Escribe tu correo'), findsOneWidget);
    expect(find.text('Escribe tu contraseña'), findsOneWidget);
    expect(repo.logins, isEmpty);
  });

  testWidgets('un correo sin formato válido da un ejemplo', (tester) async {
    await open(tester);
    await tester.enterText(
      find.byKey(LoginScreen.emailFieldKey),
      'rosa.correo',
    );
    await tester.enterText(
      find.byKey(LoginScreen.passwordFieldKey),
      'clave-segura',
    );
    await submit(tester);
    expect(find.textContaining('nombre@correo.com'), findsWidgets);
    expect(repo.logins, isEmpty);
  });

  testWidgets('ingresa con el correo sin espacios', (tester) async {
    await open(tester);
    await tester.enterText(
      find.byKey(LoginScreen.emailFieldKey),
      '  rosa@correo.com ',
    );
    await tester.enterText(
      find.byKey(LoginScreen.passwordFieldKey),
      'clave-segura',
    );
    await submit(tester);
    expect(repo.logins, [('rosa@correo.com', 'clave-segura')]);
  });

  testWidgets('el botón del ojo dice qué hace y muestra la contraseña', (
    tester,
  ) async {
    await open(tester);
    expect(find.byTooltip('Mostrar contraseña'), findsOneWidget);
    await tester.tap(find.byTooltip('Mostrar contraseña'));
    await tester.pump();
    expect(find.byTooltip('Ocultar contraseña'), findsOneWidget);
  });

  testWidgets('un error de red se explica en palabras simples', (tester) async {
    repo.error = Exception(
      'No pudimos contactar al servidor. Verifica que esté encendido, que tu celular '
      'y la computadora estén en la misma red Wi-Fi y que la app use la IP de la computadora.',
    );
    await open(tester);
    await tester.enterText(
      find.byKey(LoginScreen.emailFieldKey),
      'rosa@correo.com',
    );
    await tester.enterText(
      find.byKey(LoginScreen.passwordFieldKey),
      'clave-segura',
    );
    await submit(tester);

    expect(find.byKey(LoginScreen.errorKey), findsOneWidget);
    expect(find.textContaining('Revisa tu internet'), findsOneWidget);
    expect(find.textContaining('IP de la computadora'), findsNothing);
  });

  testWidgets('el error se oculta cuando el vecino vuelve a escribir', (
    tester,
  ) async {
    await open(
      tester,
      initial: const AuthState(
        status: AuthStatus.error,
        message: 'Correo o contraseña incorrectos',
      ),
    );
    expect(find.textContaining('no coinciden'), findsOneWidget);

    await tester.enterText(
      find.byKey(LoginScreen.passwordFieldKey),
      'otra-clave',
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(LoginScreen.errorKey), findsNothing);
  });

  testWidgets('si tarda, avisa que el servidor se está activando', (
    tester,
  ) async {
    await open(tester, initial: const AuthState.loading());
    expect(find.text('Ingresando…'), findsOneWidget);
    expect(find.byKey(LoginScreen.slowServerKey), findsNothing);

    await tester.pump(
      LoginScreen.slowServerAfter + const Duration(milliseconds: 100),
    );
    expect(find.byKey(LoginScreen.slowServerKey), findsOneWidget);
    expect(find.textContaining('hasta 30 segundos'), findsOneWidget);
  });

  test('friendlyError traduce los mensajes técnicos', () {
    expect(
      LoginScreen.friendlyError(
        'No se pudo conectar con el servidor: SocketException',
      ),
      contains('Revisa tu internet'),
    );
    expect(
      LoginScreen.friendlyError('Correo o contraseña incorrectos'),
      contains('no coinciden'),
    );
    expect(
      LoginScreen.friendlyError('El servidor respondió 503'),
      contains('unos minutos'),
    );
    expect(
      LoginScreen.friendlyError(
        'Demasiados intentos fallidos. Vuelve a intentar en 4 min.',
      ),
      contains('4 min'),
    );
    expect(
      LoginScreen.friendlyError('La cuenta ya no pertenece a un barrio activo'),
      contains('junta vecinal'),
    );
  });

  testWidgets('con texto al 200 % y pantalla chica no se desborda', (
    tester,
  ) async {
    await open(tester, textScale: 2, size: const Size(360, 640));
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Crear una cuenta'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('cumple áreas táctiles, etiquetas y contraste', (tester) async {
    final handle = tester.ensureSemantics();
    await open(
      tester,
      initial: const AuthState(
        status: AuthStatus.error,
        message: 'Correo o contraseña incorrectos',
      ),
    );
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });
}
