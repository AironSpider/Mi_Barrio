import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_barrio_app/core/ui_kit/app_theme.dart';
import 'package:mi_barrio_app/core/ui_kit/main_navigation_shell.dart';
import 'package:mi_barrio_app/core/ui_kit/quick_publish_fab.dart';
import 'package:mi_barrio_app/core/barrio_context/emergency_mode_provider.dart';
import 'package:mi_barrio_app/features/proximity_services/presentation/screens/services_directory_screen.dart';
import 'package:mi_barrio_app/features/auth_barrio/data/models/user_model.dart';
import 'package:mi_barrio_app/features/auth_barrio/domain/entities/user_entity.dart';
import 'package:mi_barrio_app/features/auth_barrio/presentation/providers/auth_provider.dart';
import 'package:mi_barrio_app/features/auth_barrio/presentation/screens/neighborhood_admin_screen.dart';
import 'package:mi_barrio_app/features/auth_barrio/presentation/screens/platform_admin_screen.dart';
import 'package:mi_barrio_app/main.dart';

Future<void> _pumpAuthenticatedApp(
  WidgetTester tester, {
  bool initialEmergencyMode = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authProvider.overrideWith(
          (ref) => AuthNotifier(
            ref.read(authRepositoryProvider),
            initialState: AuthState.authenticated(
              const UserModel(
                id: 'test-user',
                tenantId: 'test-tenant',
                fullName: 'Test User',
                role: UserRole.vecino,
                token: 'test-token',
                tenantName: 'Barrio de prueba',
                joinCode: 'TEST',
                centerLat: 0,
                centerLng: 0,
              ),
            ),
          ),
        ),
      ],
      child: MiBarrioApp(initialEmergencyMode: initialEmergencyMode),
    ),
  );
}

void main() {
  testWidgets('arranca en modo día a día con 4 pestañas y botón Publicar', (
    tester,
  ) async {
    await _pumpAuthenticatedApp(tester);

    expect(find.text('Mi Barrio'), findsOneWidget);
    expect(find.byType(NavigationDestination), findsNWidgets(4));
    for (final label in ['Servicios', 'Apoyo', 'Mapa', 'Tú']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Publicar'), findsOneWidget);
    expect(find.byType(ServicesDirectoryScreen), findsOneWidget);
    for (final oficio in [
      'Gasfitería',
      'Carpintería',
      'Electricidad',
      'Clases',
      'Mascotas',
    ]) {
      expect(find.text(oficio), findsOneWidget);
    }
    expect(find.byKey(MainNavigationShell.emergencyBannerKey), findsNothing);
  });

  testWidgets('la app muestra login y permite abrir el registro sin sesión', (
    tester,
  ) async {
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
        child: const MiBarrioApp(),
      ),
    );

    expect(find.text('Ingresar'), findsOneWidget);
    await tester.tap(find.text('Crear una cuenta'));
    await tester.pumpAndSettle();

    expect(find.text('Crear cuenta'), findsNWidgets(2));
    expect(find.text('Código de tu barrio'), findsOneWidget);
    expect(find.text('Vecino'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<UserRole>));
    await tester.pumpAndSettle();
    expect(find.text('Comerciante'), findsOneWidget);
  });

  testWidgets('el superadministrador ve el formulario de alta de barrios', (
    tester,
  ) async {
    const user = UserModel(
      id: 'platform-admin',
      tenantId: null,
      fullName: 'Super Admin',
      role: UserRole.superAdmin,
      token: 'platform-token',
      tenantName: null,
      joinCode: null,
      centerLat: null,
      centerLng: null,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith(
            (ref) => AuthNotifier(
              ref.read(authRepositoryProvider),
              initialState: AuthState.authenticated(user),
            ),
          ),
        ],
        child: const MaterialApp(home: PlatformAdminScreen(user: user)),
      ),
    );

    expect(find.text('Administración de Mi Barrio'), findsOneWidget);
    expect(find.text('Nombre del barrio'), findsOneWidget);
    expect(find.text('Crear barrio / asignar administrador'), findsOneWidget);
    expect(find.text('Código de barrio existente (opcional)'), findsOneWidget);
  });

  testWidgets('el administrador de barrio tiene su código para compartir', (
    tester,
  ) async {
    const user = UserModel(
      id: 'neighborhood-admin',
      tenantId: 'tenant-1',
      fullName: 'Jefa del barrio',
      role: UserRole.adminBarrio,
      token: 'neighborhood-token',
      tenantName: 'Barrio Centro',
      joinCode: 'MB-TEST12345',
      centerLat: -5.19,
      centerLng: -80.63,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith(
            (ref) => AuthNotifier(
              ref.read(authRepositoryProvider),
              initialState: AuthState.authenticated(user),
            ),
          ),
        ],
        child: const MaterialApp(home: NeighborhoodAdminScreen(user: user)),
      ),
    );

    expect(find.text('Barrio: Barrio Centro'), findsOneWidget);
    expect(find.text('MB-TEST12345'), findsOneWidget);
    expect(find.text('Copiar código'), findsOneWidget);
  });

  testWidgets('el selector de oficios permite filtrar el directorio', (
    tester,
  ) async {
    await _pumpAuthenticatedApp(tester);

    final chip = find.byKey(const ValueKey('service_category_GASFITERIA'));
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await tester.pump();

    expect(tester.widget<ChoiceChip>(chip).selected, isTrue);
  });

  testWidgets('las pestañas cambian el contenido', (tester) async {
    await _pumpAuthenticatedApp(tester);

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
    await _pumpAuthenticatedApp(tester);

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
    await _pumpAuthenticatedApp(tester);

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
    await _pumpAuthenticatedApp(tester);

    await tester.tap(find.byKey(QuickPublishFab.fabKey));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
  });

  testWidgets('sin onPublish, el botón (+) avisa en lugar de fallar', (
    tester,
  ) async {
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
          home: const MainNavigationShell(isEmergencyMode: false),
        ),
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
          home: MainNavigationShell(
            isEmergencyMode: false,
            onPublish: () async {
              calls++;
              return true;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(QuickPublishFab.fabKey));
    await tester.pump();
    expect(calls, 1);
    expect(find.text('Muro solidario'), findsOneWidget);
  });

  for (final emergency in [false, true]) {
    testWidgets('accesibilidad (${emergency ? 'emergencia' : 'día a día'}): '
        'áreas táctiles, etiquetas y contraste', (tester) async {
      final handle = tester.ensureSemantics();
      await _pumpAuthenticatedApp(tester, initialEmergencyMode: emergency);
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

    await _pumpAuthenticatedApp(tester, initialEmergencyMode: true);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
