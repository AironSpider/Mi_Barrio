import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mi_barrio_app/core/ui_kit/app_theme.dart';
import 'package:mi_barrio_app/features/auth_barrio/data/datasources/auth_remote_datasource.dart';
import 'package:mi_barrio_app/features/auth_barrio/data/datasources/google_sign_in_client.dart';
import 'package:mi_barrio_app/features/auth_barrio/data/models/user_model.dart';
import 'package:mi_barrio_app/features/auth_barrio/domain/entities/user_entity.dart';
import 'package:mi_barrio_app/features/auth_barrio/domain/repositories/auth_repository.dart';
import 'package:mi_barrio_app/features/auth_barrio/presentation/providers/auth_provider.dart';
import 'package:mi_barrio_app/features/auth_barrio/presentation/screens/forgot_password_screen.dart';
import 'package:mi_barrio_app/features/auth_barrio/presentation/screens/login_screen.dart';
import 'package:mi_barrio_app/features/auth_barrio/presentation/screens/register_screen.dart';
import 'package:mi_barrio_app/features/auth_barrio/presentation/screens/verify_email_screen.dart';
import 'package:mi_barrio_app/features/auth_barrio/presentation/widgets/account_widgets.dart';
import 'package:mi_barrio_app/features/auth_barrio/presentation/widgets/auth_validators.dart';

/// Cuentas reales: validaciones, Google, confirmar correo y recuperar contraseña.

UserModel _user({bool verified = true, String email = 'rosa@correo.com'}) =>
    UserModel(
      id: 'user-1',
      tenantId: 'tenant-1',
      fullName: 'Rosa Vecina',
      role: UserRole.vecino,
      token: 'token-1',
      tenantName: 'Barrio',
      joinCode: 'BARRIO-01',
      centerLat: 0,
      centerLng: 0,
      email: email,
      emailVerified: verified,
    );

class _FakeGoogle implements GoogleIdTokenSource {
  bool available = true;
  String? token = 'google-id-token';
  int signOuts = 0;

  @override
  bool get isAvailable => available;

  @override
  Future<String?> getIdToken() async => token;

  @override
  Future<void> signOut() async => signOuts++;
}

class _FakeRepo implements AuthRepository {
  final googleCalls = <(String, String?, UserRole)>[];
  final verifyCodes = <String>[];
  final resetCalls = <(String, String, String)>[];
  final resetRequests = <String>[];
  int resends = 0;
  bool googleNeedsNeighborhood = true;

  @override
  Future<UserEntity> signInWithGoogle({
    required String idToken,
    String? joinCode,
    UserRole role = UserRole.vecino,
  }) async {
    googleCalls.add((idToken, joinCode, role));
    if (joinCode == null && googleNeedsNeighborhood) {
      throw const AuthException('NEEDS_JOIN_CODE', statusCode: 428);
    }
    return _user();
  }

  @override
  Future<String> sendVerificationCode(String email) async {
    resends++;
    return 'Te enviamos un código';
  }

  @override
  Future<UserEntity> verifyEmail({
    required String email,
    required String code,
  }) async {
    verifyCodes.add(code);
    if (code != '123456') {
      throw const AuthException(
        'El código no es correcto o ya venció.',
        statusCode: 400,
      );
    }
    return _user();
  }

  @override
  Future<String> requestPasswordReset(String email) async {
    resetRequests.add(email);
    return 'ok';
  }

  @override
  Future<UserEntity> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    resetCalls.add((email, code, newPassword));
    return _user();
  }

  @override
  Future<UserEntity> login({
    required String email,
    required String password,
  }) async => _user();

  @override
  Future<UserEntity> register({
    required String fullName,
    required String email,
    required String password,
    required UserRole role,
    required String joinCode,
  }) async => _user(verified: false, email: email);

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
  }) => throw UnimplementedError();

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
  // ─────────────────────────── Validaciones ───────────────────────────
  group('Validaciones', () {
    test('correo', () {
      expect(AuthValidators.email(''), 'Escribe tu correo');
      expect(
        AuthValidators.email('rosa @correo.com'),
        'El correo no lleva espacios',
      );
      expect(AuthValidators.email('rosa@correo'), contains('Revisa tu correo'));
      expect(
        AuthValidators.email('rosa@correo.c'),
        contains('Revisa tu correo'),
      );
      expect(AuthValidators.email(' rosa@correo.com '), isNull);
    });

    test('contraseña nueva: largo, letras y números, no muy común', () {
      expect(AuthValidators.newPassword(''), 'Crea una contraseña');
      expect(AuthValidators.newPassword('ab1'), 'Usa al menos 8 caracteres');
      expect(AuthValidators.newPassword('12345678'), contains('muy fácil'));
      expect(
        AuthValidators.newPassword('soloLetras'),
        'Combina letras y números',
      );
      expect(
        AuthValidators.newPassword('99999999'),
        'Combina letras y números',
      );
      expect(AuthValidators.newPassword('barrio2026'), isNull);
    });

    test(
      'repetir contraseña, código de 6 números, nombre y código de barrio',
      () {
        final confirm = AuthValidators.confirmPassword(() => 'barrio2026');
        expect(confirm(''), 'Repite tu contraseña');
        expect(confirm('barrio2025'), 'Las contraseñas no coinciden');
        expect(confirm('barrio2026'), isNull);
        expect(AuthValidators.code('12345'), 'El código tiene 6 números');
        expect(AuthValidators.code('12a456'), 'El código tiene 6 números');
        expect(AuthValidators.code('123456'), isNull);
        expect(AuthValidators.fullName('R'), 'Escribe tu nombre');
        expect(AuthValidators.fullName('Rosa 2'), 'El nombre no lleva números');
        expect(AuthValidators.joinCode('B1'), isNotNull);
      },
    );

    test('fuerza de la contraseña', () {
      expect(AuthValidators.strength(''), 0);
      expect(AuthValidators.strength('abc'), 1);
      expect(AuthValidators.strength('12345678'), 1);
      expect(AuthValidators.strength('barrio2026'), 2);
      expect(AuthValidators.strength('barrio-Piura-2026'), 4);
      expect(AuthValidators.strengthLabel(4), 'Fuerte');
    });
  });

  // ─────────────────────────── Datos ───────────────────────────
  group('Datos', () {
    test(
      'el usuario lee email_verified; si no viene, cuenta como verificado',
      () {
        final base = {
          'id': 'u',
          'tenant_id': 't',
          'full_name': 'Rosa',
          'role': 'VECINO',
          'access_token': 'tok',
          'email': 'rosa@correo.com',
          'tenant': {
            'id': 't',
            'name': 'B',
            'join_code': 'BARRIO-01',
            'center_lat': 0,
            'center_lng': 0,
          },
        };
        final nuevo = UserModel.fromJson({...base, 'email_verified': false});
        expect(nuevo.emailVerified, isFalse);
        expect(nuevo.email, 'rosa@correo.com');
        expect(
          UserModel.fromJson(base).emailVerified,
          isTrue,
          reason: 'sesiones de versiones viejas',
        );
        final guardado = UserModel.fromStoredJson(nuevo.toJson());
        expect(
          guardado.emailVerified,
          isFalse,
          reason: 'se guarda al cerrar y abrir la app',
        );
      },
    );

    test(
      'Google: manda el token, el barrio y el rol; 428 = falta el barrio',
      () async {
        final bodies = <Map<String, dynamic>>[];
        final remote = AuthRemoteDatasource(
          baseUrl: 'http://api',
          client: MockClient((request) async {
            bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
            expect(request.url.path, '/api/v1/auth/google');
            return http.Response(
              jsonEncode({'detail': 'NEEDS_JOIN_CODE'}),
              428,
            );
          }),
        );
        await expectLater(
          remote.googleLogin(
            idToken: 'tok-123456789012345678',
            joinCode: ' barrio-01 ',
            role: 'COMERCIANTE',
          ),
          throwsA(
            isA<AuthException>().having((e) => e.statusCode, 'status', 428),
          ),
        );
        expect(bodies.single, {
          'id_token': 'tok-123456789012345678',
          'join_code': 'BARRIO-01',
          'role': 'COMERCIANTE',
        });
      },
    );

    test(
      'recuperar contraseña manda correo en minúsculas, código y contraseña',
      () async {
        late Map<String, dynamic> body;
        final remote = AuthRemoteDatasource(
          baseUrl: 'http://api',
          client: MockClient((request) async {
            body = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response(
              jsonEncode({'message': 'Si hay una cuenta...'}),
              200,
            );
          }),
        );
        expect(
          await remote.requestPasswordReset(' Rosa@Correo.com '),
          'Si hay una cuenta...',
        );
        expect(body, {'email': 'rosa@correo.com'});
      },
    );
  });

  // ─────────────────────────── Pantallas ───────────────────────────
  late _FakeRepo repo;
  late _FakeGoogle google;

  setUp(() {
    repo = _FakeRepo();
    google = _FakeGoogle();
  });

  /// Como pumpAndSettle, pero sin esperar a que paren los indicadores de carga.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  Future<ProviderContainer> pump(
    WidgetTester tester,
    Widget Function(WidgetRef ref) home, {
    AuthState initial = const AuthState.unauthenticated(),
  }) async {
    tester.view.physicalSize = const Size(412, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(
          (ref) => AuthNotifier(repo, initialState: initial),
        ),
        googleIdTokenSourceProvider.overrideWithValue(google),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.day(),
          home: Consumer(builder: (context, ref, _) => home(ref)),
        ),
      ),
    );
    return container;
  }

  testWidgets(
    'login: el botón de Google con su logo; en la PC explica que es del celular',
    (tester) async {
      await pump(tester, (_) => const LoginScreen());
      expect(find.byKey(GoogleSignInButton.buttonKey), findsOneWidget);
      expect(find.text('Continuar con Google'), findsOneWidget);
      expect(
        find.byType(SvgPicture),
        findsOneWidget,
        reason: 'logo oficial de Google',
      );

      google.available = false; // Windows
      await tester.tap(find.byKey(GoogleSignInButton.buttonKey));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('funciona en la app del celular'),
        findsOneWidget,
      );
      expect(repo.googleCalls, isEmpty);
    },
  );

  testWidgets('login con Google, cuenta nueva: pide el barrio y entra', (
    tester,
  ) async {
    final container = await pump(tester, (_) => const LoginScreen());
    await tester.tap(find.byKey(GoogleSignInButton.buttonKey));
    await settle(tester);

    expect(
      find.text('Un paso más'),
      findsOneWidget,
      reason: 'primera vez con Google',
    );
    await tester.tap(find.text('Entrar a mi barrio'));
    await settle(tester);
    expect(find.text('Escribe el código de tu barrio'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('google_join_code')),
      'barrio-01',
    );
    await tester.tap(find.text('Tengo un negocio y quiero gestionarlo'));
    await tester.tap(find.text('Entrar a mi barrio'));
    await settle(tester);

    expect(repo.googleCalls.length, 2);
    expect(repo.googleCalls.last.$2, 'BARRIO-01');
    expect(repo.googleCalls.last.$3, UserRole.comerciante);
    expect(container.read(authProvider).user?.id, 'user-1');
  });

  testWidgets('login con Google, cuenta que ya existe: entra directo', (
    tester,
  ) async {
    repo.googleNeedsNeighborhood = false;
    final container = await pump(tester, (_) => const LoginScreen());
    await tester.tap(find.byKey(GoogleSignInButton.buttonKey));
    await settle(tester);
    expect(find.text('Un paso más'), findsNothing);
    expect(repo.googleCalls.single.$2, isNull);
    expect(container.read(authProvider).user, isNotNull);
  });

  testWidgets('login con Google: si cierra la ventana no pasa nada', (
    tester,
  ) async {
    google.token = null;
    final container = await pump(tester, (_) => const LoginScreen());
    await tester.tap(find.byKey(GoogleSignInButton.buttonKey));
    await tester.pumpAndSettle();
    expect(repo.googleCalls, isEmpty);
    expect(container.read(authProvider).user, isNull);
    expect(find.byKey(LoginScreen.googleErrorKey), findsNothing);
  });

  testWidgets(
    '"¿Olvidaste tu contraseña?" abre la recuperación con el correo escrito',
    (tester) async {
      await pump(tester, (_) => const LoginScreen());
      await tester.enterText(
        find.byKey(LoginScreen.emailFieldKey),
        'rosa@correo.com',
      );
      await tester.tap(find.byKey(LoginScreen.forgotPasswordKey));
      await tester.pumpAndSettle();
      expect(find.byType(ForgotPasswordScreen), findsOneWidget);
      expect(
        find.widgetWithText(TextFormField, 'rosa@correo.com'),
        findsOneWidget,
      );
    },
  );

  testWidgets('recuperar contraseña: código, contraseña nueva y repetirla', (
    tester,
  ) async {
    final container = await pump(
      tester,
      (_) => const ForgotPasswordScreen(initialEmail: 'rosa@correo.com'),
    );
    await tester.tap(find.byKey(ForgotPasswordScreen.sendKey));
    await settle(tester);
    expect(repo.resetRequests, ['rosa@correo.com']);
    expect(find.text('Escribe el código'), findsOneWidget);

    await tester.enterText(
      find.byKey(ForgotPasswordScreen.codeFieldKey),
      '654321',
    );
    await tester.enterText(
      find.byKey(ForgotPasswordScreen.passwordFieldKey),
      'barrio2026',
    );
    await tester.enterText(
      find.byKey(ForgotPasswordScreen.confirmFieldKey),
      'barrio2025',
    );
    await tester.ensureVisible(find.byKey(ForgotPasswordScreen.saveKey));
    await tester.tap(find.byKey(ForgotPasswordScreen.saveKey));
    await settle(tester);
    expect(find.text('Las contraseñas no coinciden'), findsOneWidget);
    expect(repo.resetCalls, isEmpty);

    await tester.enterText(
      find.byKey(ForgotPasswordScreen.confirmFieldKey),
      'barrio2026',
    );
    await tester.tap(find.byKey(ForgotPasswordScreen.saveKey));
    await settle(tester);
    expect(repo.resetCalls.single, ('rosa@correo.com', '654321', 'barrio2026'));
    expect(
      container.read(authProvider).user,
      isNotNull,
      reason: 'queda con la sesión iniciada',
    );
  });

  testWidgets(
    'confirmar correo: código malo muestra el error y el bueno entra',
    (tester) async {
      final container = await pump(
        tester,
        (_) => VerifyEmailScreen(user: _user(verified: false)),
        initial: AuthState.authenticated(_user(verified: false)),
      );
      expect(find.textContaining('rosa@correo.com'), findsOneWidget);
      expect(
        find.text('Reenviar código en 60 s'),
        findsOneWidget,
        reason: 'espera antes de reenviar',
      );

      await tester.enterText(
        find.byKey(VerifyEmailScreen.codeFieldKey),
        '111111',
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('no es correcto'), findsOneWidget);
      expect(container.read(authProvider).user?.emailVerified, isFalse);

      await tester.enterText(
        find.byKey(VerifyEmailScreen.codeFieldKey),
        '123456',
      );
      await tester.pumpAndSettle();
      expect(repo.verifyCodes, ['111111', '123456']);
      expect(container.read(authProvider).user?.emailVerified, isTrue);
    },
  );

  testWidgets('confirmar correo: "Reenviar código" se activa a los 60 s', (
    tester,
  ) async {
    await pump(
      tester,
      (_) => VerifyEmailScreen(user: _user(verified: false)),
      initial: AuthState.authenticated(_user(verified: false)),
    );
    await tester.pump(const Duration(seconds: 61));
    expect(find.text('Reenviar código'), findsOneWidget);
    await tester.tap(find.byKey(VerifyEmailScreen.resendKey));
    await tester.pump();
    await tester.pump();
    expect(repo.resends, 1);
    expect(find.text('Listo: te enviamos un código nuevo.'), findsOneWidget);
  });

  testWidgets('registro: valida correo, contraseña segura y que coincidan', (
    tester,
  ) async {
    await pump(
      tester,
      (_) => RegisterScreen(lookupNeighborhood: (_) async => 'Barrio'),
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Código de tu barrio'),
      'BARRIO-01',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nombre completo'),
      'Rosa Vecina',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Correo electrónico'),
      'rosa@correo',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Contraseña'),
      '12345678',
    );
    await tester.pump();
    expect(find.byKey(PasswordStrengthMeter.meterKey), findsOneWidget);
    expect(find.text('Débil'), findsOneWidget);
    await tester.enterText(
      find.byKey(RegisterScreen.confirmFieldKey),
      '1234567',
    );
    await tester.ensureVisible(find.byKey(RegisterScreen.submitKey));
    await tester.tap(find.byKey(RegisterScreen.submitKey));
    await tester.pump();

    expect(find.textContaining('Revisa tu correo'), findsOneWidget);
    expect(find.textContaining('muy fácil'), findsOneWidget);
    expect(find.text('Las contraseñas no coinciden'), findsOneWidget);
  });

  testWidgets('registro con Google: primero pide el código del barrio', (
    tester,
  ) async {
    await pump(
      tester,
      (_) => RegisterScreen(lookupNeighborhood: (_) async => 'Barrio'),
    );
    expect(find.text('Registrarme con Google'), findsOneWidget);
    await tester.tap(find.text('Registrarme con Google'));
    await tester.pump();
    expect(
      find.text('Primero escribe el código de tu barrio.'),
      findsOneWidget,
    );
    expect(repo.googleCalls, isEmpty);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Código de tu barrio'),
      'barrio-01',
    );
    await tester.tap(find.text('Registrarme con Google'));
    await settle(tester);
    expect(repo.googleCalls.single.$2, 'barrio-01');
  });
}
