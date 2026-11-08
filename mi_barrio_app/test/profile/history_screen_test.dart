import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_barrio_app/core/barrio_context/tenant_session.dart';
import 'package:mi_barrio_app/core/database_sqlite/sqlite_database.dart';
import 'package:mi_barrio_app/core/ui_kit/app_theme.dart';
import 'package:mi_barrio_app/core/ui_kit/sync_status_chip.dart';
import 'package:mi_barrio_app/features/profile_me/presentation/screens/history_screen.dart';
import 'package:mi_barrio_app/features/proximity_services/data/datasources/services_sqlite_ds.dart';
import 'package:mi_barrio_app/features/proximity_services/data/models/service_model.dart';
import 'package:mi_barrio_app/features/solidarity_network/data/datasources/solidarity_sqlite_ds.dart';
import 'package:mi_barrio_app/features/solidarity_network/data/models/solidarity_post_model.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  const tenant = 'a1b2c3d4-e5f6-4a8b-9c0d-1e2f3a4b5c6d';
  const me = '5f3a2c1b-1234-4abc-9def-0123456789ab';
  const other = '9a8b7c6d-5e4f-4a3b-8c2d-1e0f9a8b7c6d';
  final local = LocalDatabase.instance;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
  });
  setUp(() => local.resetForTesting(path: inMemoryDatabasePath));
  tearDown(() => local.close());

  Future<void> seed(WidgetTester tester) => tester.runAsync(() async {
        final posts = SolidaritySqliteDatasource();
        for (final (author, title) in [(me, 'Préstamo de escalera'), (me, 'Ofrezco clases'), (other, 'De otro')]) {
          await posts.publishInThreeClicks(
            tenantId: tenant,
            authorUserId: author,
            modality: SolidarityModality.prestamoHerramienta,
            title: title,
            lat: -5.1945,
            lng: -80.6328,
          );
        }
        await ServicesSqliteDatasource().insertService(
          tenantId: tenant,
          providerUserId: me,
          category: ServiceCategory.gasfiteria,
          title: 'Gasfitero 24h',
          lat: -5.1945,
          lng: -80.6328,
        );
      });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.day(),
      home: const HistoryScreen(tenantId: tenant, userId: me),
    ));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();
  }

  testWidgets('3 pestañas con contador y solo lo propio', (tester) async {
    await seed(tester);
    await open(tester);

    expect(find.text('Mis servicios (1)'), findsOneWidget);
    expect(find.text('Mis favores (2)'), findsOneWidget);
    expect(find.text('Mis SOS (0)'), findsOneWidget);
    // Un vecino abre directo en "Mis favores".
    expect(find.text('Préstamo de escalera'), findsOneWidget);
    await tester.tap(find.text('Mis servicios (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Gasfitero 24h'), findsOneWidget);
    expect(find.text('Gasfitería'), findsOneWidget);

    await tester.tap(find.text('Mis favores (2)'));
    await tester.pumpAndSettle();
    expect(find.text('Préstamo de escalera'), findsOneWidget);
    expect(find.text('De otro'), findsNothing);
    expect(find.text('Disponible'), findsNWidgets(2));
  });

  testWidgets('cada ítem sin subir lleva el chip "Pendiente"', (tester) async {
    await seed(tester);
    await open(tester);
    await tester.tap(find.text('Mis favores (2)'));
    await tester.pumpAndSettle();
    final chips = tester.widgetList<SyncStatusChip>(find.byType(SyncStatusChip));
    expect(chips.map((c) => c.status), everyElement(SyncChipStatus.pending));
    expect(find.text('Pendiente'), findsWidgets);
  });

  testWidgets('sin datos muestra mensajes claros por pestaña', (tester) async {
    await open(tester);
    await tester.tap(find.text('Mis servicios (0)'));
    await tester.pumpAndSettle();
    expect(find.text('Aún no ofreces servicios.'), findsOneWidget);
    await tester.tap(find.text('Mis SOS (0)'));
    await tester.pumpAndSettle();
    expect(find.text('Aún no creaste alertas.'), findsOneWidget);
  });

  testWidgets('un comerciante abre en "Mis servicios"', (tester) async {
    await seed(tester);
    TenantSession.instance.role = 'COMERCIANTE';
    addTearDown(() => TenantSession.instance.role = 'VECINO');
    await open(tester);
    expect(find.text('Gasfitero 24h'), findsOneWidget);
  });

  testWidgets('las pestañas se leen sobre la barra (no verde sobre verde)', (tester) async {
    await seed(tester);
    await open(tester);
    final bar = tester.widget<TabBar>(find.byKey(HistoryScreen.tabBarKey));
    final fondo = Theme.of(tester.element(find.byType(AppBar))).appBarTheme.backgroundColor!;
    double lum(Color c) => c.computeLuminance();
    double ratio(Color a, Color b) {
      final (x, y) = (lum(a), lum(b));
      return (x > y ? x + 0.05 : y + 0.05) / (x > y ? y + 0.05 : x + 0.05);
    }
    expect(ratio(bar.labelColor!, fondo), greaterThanOrEqualTo(4.5));
    expect(ratio(bar.unselectedLabelColor!, fondo), greaterThanOrEqualTo(4.5));
  });

  testWidgets('accesible: áreas táctiles, etiquetas y contraste', (tester) async {
    final handle = tester.ensureSemantics();
    await seed(tester);
    await open(tester);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });
}
