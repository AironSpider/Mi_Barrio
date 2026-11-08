import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_barrio_app/core/barrio_context/emergency_mode_provider.dart';
import 'package:mi_barrio_app/core/barrio_context/tenant_session.dart';
import 'package:mi_barrio_app/core/database_sqlite/local_id.dart';
import 'package:mi_barrio_app/core/database_sqlite/sqlite_database.dart';
import 'package:mi_barrio_app/core/database_sqlite/sqlite_tables.dart';
import 'package:mi_barrio_app/core/ui_kit/app_theme.dart';
import 'package:mi_barrio_app/core/ui_kit/dev_tools.dart';
import 'package:mi_barrio_app/core/ui_kit/done_confirmation.dart';
import 'package:mi_barrio_app/features/auth_barrio/presentation/providers/auth_provider.dart';
import 'package:mi_barrio_app/features/auth_barrio/presentation/screens/register_screen.dart';
import 'package:mi_barrio_app/features/proximity_services/presentation/screens/services_directory_screen.dart';
import 'package:mi_barrio_app/features/solidarity_network/data/models/solidarity_post_model.dart';
import 'package:mi_barrio_app/features/solidarity_network/presentation/screens/collaborative_wall_screen.dart';
import 'package:mi_barrio_app/features/solidarity_network/presentation/widgets/post_meta_label.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Sprint 13 · Dev 3 · Bloque A: registro con 2 tarjetas, aviso de aprobación,
/// "¡Listo!", "hace 2 h · a 300 m" y sin interruptor 🐞 en la demo.
void main() {
  final local = LocalDatabase.instance;
  final tenant = LocalId.generate();
  final me = LocalId.generate();
  const lat = -5.1945;
  const lng = -80.6328;

  void login({String role = 'VECINO', bool approved = true}) {
    TenantSession.instance.applyAuthenticatedUser(
      authenticatedTenantId: tenant,
      authenticatedUserId: me,
      authenticatedTenantName: 'Barrio',
      authenticatedRole: role,
      authenticatedIsApproved: approved,
      authenticatedCenterLat: lat,
      authenticatedCenterLng: lng,
    );
  }

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
  });
  setUp(() async {
    await local.resetForTesting(path: inMemoryDatabasePath);
    login();
    EmergencyModeProvider.instance.resetForTesting();
  });
  tearDown(() async {
    EmergencyModeProvider.instance.resetForTesting();
    login();
    await local.close();
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump();
    }
  }

  Widget app(Widget home) =>
      MaterialApp(theme: AppTheme.of(isEmergency: false), home: home);

  void tallScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  group('Interruptor 🐞', () {
    test('en pruebas (debug sin API_BASE_URL) sigue disponible', () {
      // El build de demo usa release o --dart-define=API_BASE_URL, y ahí se apaga.
      expect(DevTools.enabled, isTrue);
    });
  });

  group('Registro con 2 tarjetas', () {
    testWidgets('muestra vecino y comerciante; tocar cambia la selección', (
      tester,
    ) async {
      tallScreen(tester);
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
          child: app(const RegisterScreen()),
        ),
      );

      expect(find.byKey(RegisterScreen.vecinoCardKey), findsOneWidget);
      expect(find.byKey(RegisterScreen.comercianteCardKey), findsOneWidget);
      expect(find.byType(DropdownButtonFormField), findsNothing);

      bool selected(Key key) => tester.any(
        find.descendant(
          of: find.byKey(key),
          matching: find.byIcon(Icons.check_circle_rounded),
        ),
      );

      expect(selected(RegisterScreen.vecinoCardKey), isTrue);
      expect(selected(RegisterScreen.comercianteCardKey), isFalse);

      await tester.tap(find.byKey(RegisterScreen.comercianteCardKey));
      await tester.pump();
      expect(selected(RegisterScreen.vecinoCardKey), isFalse);
      expect(selected(RegisterScreen.comercianteCardKey), isTrue);
      expect(find.textContaining('La junta aprueba mi cuenta'), findsOneWidget);
    });
  });

  group('Aviso de aprobación junto a "Ofrecer servicio"', () {
    Future<void> pumpMerchant(WidgetTester tester, {required bool approved}) async {
      login(role: 'COMERCIANTE', approved: approved);
      await tester.runAsync(() async {
        await (await local.database).insert('users', {
          'id': me,
          'tenant_id': tenant,
          'full_name': 'Don Pepe',
          'role': 'COMERCIANTE',
          'home_lat': lat,
          'home_lng': lng,
          'updated_at': '2026-11-07T10:00:00Z',
          'sync_status': SqliteTables.syncSynced,
        });
      });
      tallScreen(tester);
      await tester.pumpWidget(
        app(Scaffold(body: ServicesDirectoryScreen(tenantId: tenant, userId: me))),
      );
      await settle(tester);
    }

    testWidgets('comerciante sin aprobar ve el aviso', (tester) async {
      await pumpMerchant(tester, approved: false);
      expect(find.text('Ofrecer servicio'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('offer_service_approval_notice')),
        findsOneWidget,
      );
      expect(find.textContaining('espera la aprobación de la junta'), findsOneWidget);
    });

    testWidgets('comerciante aprobado no ve el aviso', (tester) async {
      await pumpMerchant(tester, approved: true);
      expect(find.text('Ofrecer servicio'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('offer_service_approval_notice')),
        findsNothing,
      );
    });
  });

  group('Confirmación "¡Listo!"', () {
    testWidgets('muestra ¡Listo! con el detalle', (tester) async {
      await tester.pumpWidget(
        app(
          Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => DoneConfirmation.show(
                  ScaffoldMessenger.of(context),
                  'Tu publicación ya está en el muro.',
                ),
                child: const Text('publicar'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('publicar'));
      await tester.pump();
      expect(find.byKey(DoneConfirmation.snackBarKey), findsOneWidget);
      expect(find.text('¡Listo!'), findsOneWidget);
      expect(find.text('Tu publicación ya está en el muro.'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    });
  });

  group('"hace 2 h · a 300 m" en el muro', () {
    final now = DateTime.utc(2026, 11, 8, 12);

    test('tiempo en lenguaje simple', () {
      String? t(Duration d) =>
          PostMetaLabel.timeAgo(now.subtract(d).toIso8601String(), now: now);
      expect(t(const Duration(seconds: 20)), 'hace un momento');
      expect(t(const Duration(minutes: 5)), 'hace 5 min');
      expect(t(const Duration(hours: 2)), 'hace 2 h');
      expect(t(const Duration(hours: 30)), 'ayer');
      expect(t(const Duration(days: 3)), 'hace 3 días');
      expect(PostMetaLabel.timeAgo('no-es-fecha'), isNull);
    });

    test('distancia y unión con " · "', () {
      expect(PostMetaLabel.distance(0.3), 'a 300 m');
      expect(PostMetaLabel.distance(2.4), 'a 2,4 km');
      expect(PostMetaLabel.distance(0.01), 'muy cerca');
      expect(
        PostMetaLabel.build(
          updatedAtIso: now.subtract(const Duration(hours: 2)).toIso8601String(),
          distanceKm: 0.3,
          now: now,
        ),
        'hace 2 h · a 300 m',
      );
      expect(PostMetaLabel.build(updatedAtIso: 'x', distanceKm: 0.3), 'a 300 m');
    });

    testWidgets('la tarjeta del favor muestra hace … · a … m', (tester) async {
      // ~300 m al norte del centro del barrio.
      await tester.runAsync(() async {
        await (await local.database).insert(
          SolidarityPostModel.table,
          SolidarityPostModel(
            id: 'p1',
            tenantId: tenant,
            authorUserId: LocalId.generate(),
            flowType: SolidarityFlowType.solicitoAyuda,
            modality: SolidarityModality.prestamoHerramienta,
            title: 'Necesito una escalera',
            status: SolidarityStatus.disponible,
            lat: lat + 0.0027,
            lng: lng,
            updatedAt: DateTime.now()
                .toUtc()
                .subtract(const Duration(hours: 2, minutes: 5))
                .toIso8601String(),
            syncStatus: SqliteTables.syncSynced,
          ).toSqlite(),
        );
      });
      tallScreen(tester);
      await tester.pumpWidget(
        app(Scaffold(body: CollaborativeWallScreen(tenantId: tenant))),
      );
      await settle(tester);

      expect(find.byKey(const ValueKey('favor_meta_p1')), findsOneWidget);
      expect(find.text('hace 2 h · a 300 m'), findsOneWidget);
    });
  });
}
