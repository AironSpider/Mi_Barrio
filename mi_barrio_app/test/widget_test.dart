import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_barrio_app/core/ui_kit/app_theme.dart';
import 'package:mi_barrio_app/core/ui_kit/main_navigation_shell.dart';
import 'package:mi_barrio_app/core/ui_kit/quick_publish_fab.dart';
import 'package:mi_barrio_app/core/ui_kit/search_filter_bar.dart';
import 'package:mi_barrio_app/core/barrio_context/emergency_mode_provider.dart';
import 'package:mi_barrio_app/features/emergency_support/presentation/providers/emergency_provider.dart';
import 'package:mi_barrio_app/features/proximity_services/presentation/screens/services_directory_screen.dart';
import 'package:mi_barrio_app/features/auth_barrio/data/models/user_model.dart';
import 'package:mi_barrio_app/features/auth_barrio/domain/entities/user_entity.dart';
import 'package:mi_barrio_app/features/auth_barrio/presentation/providers/auth_provider.dart';
import 'package:mi_barrio_app/features/auth_barrio/presentation/screens/neighborhood_admin_screen.dart';
import 'package:mi_barrio_app/features/auth_barrio/presentation/screens/platform_admin_screen.dart';
import 'package:mi_barrio_app/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpAuthenticatedApp(
  WidgetTester tester, {
  bool initialEmergencyMode = false,
}) async {
  SharedPreferences.setMockInitialValues({});
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
  await tester.pump(); // TutorialGate termina de leer la bandera
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
    // Los oficios están en el modal de filtros (botón junto al buscador).
    await tester.tap(find.byKey(const ValueKey('services_filters_button')));
    await tester.pumpAndSettle();
    for (final oficio in [
      'Gasfitería',
      'Carpintería',
      'Electricidad',
      'Clases',
      'Mascotas',
    ]) {
      expect(find.text(oficio), findsOneWidget);
    }
    await tester.tap(find.byTooltip('Cerrar'));
    await tester.pumpAndSettle();
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
    await tester.ensureVisible(find.text('Crear una cuenta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Crear una cuenta'));
    await tester.pumpAndSettle();

    expect(find.text('Crear cuenta'), findsNWidgets(2));
    expect(find.text('Código de tu barrio'), findsOneWidget);
    expect(find.text('Soy vecino'), findsOneWidget);
    expect(find.text('Tengo un negocio y quiero gestionarlo'), findsOneWidget);
  });

  testWidgets('el superadministrador ve el formulario de alta de barrios', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 4800);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
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
        child: MaterialApp(
          home: PlatformAdminScreen(
            user: user,
            loadNeighborhoods: () async => const [
              NeighborhoodSummary(
                id: 'n1',
                name: 'Barrio Los Algarrobos',
                inviteCode: 'MB-ALGARROBO1',
                isEmergencyActive: false,
                adminCount: 0,
              ),
              NeighborhoodSummary(
                id: 'n2',
                name: 'Barrio Centro',
                inviteCode: 'MB-CENTRO0001',
                isEmergencyActive: true,
                adminCount: 1,
              ),
            ],
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('Administración de Mi Barrio'), findsOneWidget);
    // Lista real de barrios (del servidor), sin datos fijos.
    expect(find.text('Barrios (2)'), findsOneWidget);
    expect(find.text('Barrio Los Algarrobos'), findsOneWidget);
    expect(find.text('Sin administrador'), findsOneWidget);
    expect(find.text('En emergencia'), findsOneWidget);
    expect(find.text('Nombre del barrio'), findsOneWidget);
    expect(find.text('Crear barrio'), findsOneWidget);
    expect(find.text('Usar mi ubicación'), findsOneWidget);

    // "Asignar administrador" en un barrio sin junta llena el código.
    await tester.tap(find.text('Asignar administrador').first);
    await tester.pumpAndSettle();
    expect(find.text('MB-ALGARROBO1'), findsWidgets);
    expect(find.text('Código del barrio'), findsOneWidget);
    expect(find.text('Nombre del barrio'), findsNothing);
    expect(find.text('Latitud'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(PlatformAdminScreen.submitKey),
        matching: find.text('Asignar administrador'),
      ),
      findsOneWidget,
    );
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

    final button = find.byKey(const ValueKey('services_filters_button'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();

    final pill = find.byKey(const ValueKey('filter_option_oficio_GASFITERIA'));
    await tester.ensureVisible(pill);
    await tester.pumpAndSettle();
    await tester.tap(pill);
    await tester.pump();
    expect(tester.widget<FilterPill>(pill).selected, isTrue);

    await tester.tap(find.byKey(const ValueKey('filters_apply')));
    await tester.pumpAndSettle();
    expect(tester.widget<FilterButton>(find.byType(FilterButton).first).activeCount, 1);
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
    expect(find.text('Ayuda'), findsOneWidget);

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

  testWidgets('en Servicios, Publicar abre el formulario de servicio', (
    tester,
  ) async {
    HelpLocator.resolve = () async =>
        const HelpLocation(lat: -5.1945, lng: -80.6328, fromGps: false);
    await _pumpAuthenticatedApp(tester);

    await tester.tap(find.byKey(QuickPublishFab.fabKey));
    await tester.pumpAndSettle();
    expect(find.text('Pedir un servicio'), findsOneWidget);
    expect(find.text('Brindar'), findsOneWidget);
  });

  testWidgets('en Apoyo, Publicar abre la pantalla de apoyo', (tester) async {
    HelpLocator.resolve = () async =>
        const HelpLocation(lat: -5.1945, lng: -80.6328, fromGps: false);
    await _pumpAuthenticatedApp(tester);

    await tester.tap(find.text('Apoyo'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(QuickPublishFab.fabKey));
    await tester.pumpAndSettle();
    expect(find.text('Pedir apoyo'), findsOneWidget);
    expect(find.text('Otro'), findsOneWidget);
  });

  testWidgets('en el Mapa no hay botón Publicar (día a día)', (tester) async {
    await _pumpAuthenticatedApp(tester);
    await tester.tap(find.text('Mapa'));
    await tester.pumpAndSettle();
    expect(find.byKey(QuickPublishFab.fabKey), findsNothing);
  });

  testWidgets('en emergencia, "Ayuda" (sin ícono) llama a onPublish y muestra el Mapa', (
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
          theme: AppTheme.emergency(),
          home: MainNavigationShell(
            isEmergencyMode: true,
            onPublish: () async {
              calls++;
              return true;
            },
          ),
        ),
      ),
    );

    expect(find.text('Ayuda'), findsOneWidget);
    expect(find.byIcon(Icons.sos_rounded), findsNothing);
    await tester.tap(find.byKey(QuickPublishFab.fabKey));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('Mapa de ayuda'), findsOneWidget);
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
