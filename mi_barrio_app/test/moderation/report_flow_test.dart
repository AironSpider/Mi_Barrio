import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_barrio_app/core/database_sqlite/local_id.dart';
import 'package:mi_barrio_app/core/database_sqlite/sqlite_database.dart';
import 'package:mi_barrio_app/core/ui_kit/app_theme.dart';
import 'package:mi_barrio_app/core/ui_kit/search_filter_bar.dart';
import 'package:mi_barrio_app/features/moderation/data/content_reports.dart';
import 'package:mi_barrio_app/features/moderation/presentation/report_flow.dart';
import 'package:mi_barrio_app/features/proximity_services/data/datasources/services_sqlite_ds.dart';
import 'package:mi_barrio_app/features/solidarity_network/data/datasources/solidarity_sqlite_ds.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../flutter_test_config.dart';

void main() {
  final local = LocalDatabase.instance;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() => local.resetForTesting(path: inMemoryDatabasePath));
  tearDown(() => local.close());

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump();
    }
  }

  Future<void> pumpButton(WidgetTester tester, String targetId, {VoidCallback? onReported}) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.day(),
      home: Scaffold(
        body: Center(
          child: ReportButton(
            targetType: ReportTarget.post,
            targetId: targetId,
            onReported: onReported,
          ),
        ),
      ),
    ));
  }

  testWidgets('motivo → confirmar (Regresar conserva lo elegido) → listo', (tester) async {
    final target = LocalId.generate();
    var reported = false;
    await pumpButton(tester, target, onReported: () => reported = true);

    await tester.tap(find.byKey(ReportButton.buttonKey));
    await settle(tester);
    expect(find.text('Si deseas reportar esta publicación, cuéntanos el motivo:'), findsOneWidget);
    for (final label in ReportReason.labels.values) {
      expect(find.text(label), findsOneWidget);
    }
    // Sin motivo no se puede enviar; "Otro" pide escribirlo.
    final send = find.byKey(const ValueKey('report_send'));
    expect(tester.widget<FilledButton>(send).onPressed, isNull);
    await tester.tap(find.text('Otro'));
    await settle(tester);
    expect(tester.widget<FilledButton>(send).onPressed, isNull);
    await tester.enterText(find.byKey(const ValueKey('report_detail')), 'Vende cosas robadas');
    await tester.pump();
    await tester.tap(send);
    await settle(tester);

    // Un solo modal a la vez.
    expect(find.text('¿Está seguro de reportar esta publicación?'), findsOneWidget);
    expect(find.text('Si deseas reportar esta publicación, cuéntanos el motivo:'), findsNothing);

    // Regresar: vuelve el primero con lo escrito.
    await tester.tap(find.byKey(const ValueKey('report_back')));
    await settle(tester);
    expect(find.text('Vende cosas robadas'), findsOneWidget);
    await tester.tap(send);
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('report_confirm')));
    await settle(tester);

    expect(find.text('Gracias, revisaremos tu reporte'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('report_done')));
    await settle(tester);
    expect(reported, isTrue);

    final db = (await tester.runAsync(() => local.database))!;
    final rows = await tester.runAsync(() => db.query('content_reports'));
    expect(rows!.single['reason'], ReportReason.otro);
    expect(rows.single['detail'], 'Vende cosas robadas');
    final outbox = await tester.runAsync(() => db.query('sync_outbox'));
    expect(outbox!.single['target_table'], 'content_reports');

    // No se puede reportar dos veces.
    await tester.tap(find.byKey(ReportButton.buttonKey));
    await settle(tester);
    expect(find.text('Ya reportaste esta publicación. La estamos revisando.'), findsOneWidget);
  });

  test('lo reportado o en revisión no se le muestra a quien reporta', () async {
    final wall = SolidaritySqliteDatasource();
    final services = ServicesSqliteDatasource();
    final post = await wall.publishInThreeClicks(
      tenantId: testTenantId,
      authorUserId: LocalId.generate(),
      modality: 'AYUDA_TEMPORAL',
      title: 'Favor ajeno',
      lat: -5.19,
      lng: -80.63,
    );
    final svc = await services.insertService(
      tenantId: testTenantId,
      providerUserId: LocalId.generate(),
      category: 'GASFITERIA',
      title: 'Gasfitero',
      lat: -5.19,
      lng: -80.63,
      flowType: 'SOLICITO_AYUDA',
    );
    expect((await services.getServices(testTenantId)).single.isNeed, isTrue);

    await ContentReportsDatasource().report(
      targetType: ReportTarget.post,
      targetId: post.id,
      reason: ReportReason.spam,
    );
    expect(await wall.getActivePosts(testTenantId), isEmpty);

    final db = await local.database;
    await db.update('local_services', {'is_under_review': 1}, where: 'id = ?', whereArgs: [svc.id]);
    expect(await services.getServices(testTenantId), isEmpty);
  });

  testWidgets('el interruptor del modal de filtros cuenta como filtro activo', (tester) async {
    FilterSelection? result;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.day(),
      home: Scaffold(
        body: SearchFilterBar(
          hintText: 'Buscar',
          onSearchChanged: (_) {},
          groups: const [FilterGroup.toggle(id: 'mios', title: 'Seleccionar los míos')],
          selection: const {},
          onFiltersChanged: (v) => result = v,
        ),
      ),
    ));
    await tester.tap(find.byType(FilterButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('filter_toggle_mios')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('filters_apply')));
    await tester.pumpAndSettle();
    expect(isToggleOn(result!, 'mios'), isTrue);
    expect(activeFilterCount(result!), 1);
  });
}
