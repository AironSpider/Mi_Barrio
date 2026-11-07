import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_barrio_app/core/database_sqlite/local_id.dart';
import 'package:mi_barrio_app/core/database_sqlite/sqlite_database.dart';
import 'package:mi_barrio_app/core/sync_manager/sync_coordinator.dart';
import 'package:mi_barrio_app/core/ui_kit/app_theme.dart';
import 'package:mi_barrio_app/features/proximity_services/data/datasources/services_sqlite_ds.dart';
import 'package:mi_barrio_app/features/proximity_services/data/models/service_model.dart';
import 'package:mi_barrio_app/features/proximity_services/presentation/widgets/service_detail_sheet.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  final local = LocalDatabase.instance;
  final tenantId = LocalId.generate();
  final neighborId = LocalId.generate();
  final providerId = LocalId.generate();
  late LocalServiceModel service;
  late ValueNotifier<SyncPhase> phase;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await local.resetForTesting(path: inMemoryDatabasePath);
    await ServicesSqliteDatasource().insertService(
      tenantId: tenantId,
      providerUserId: providerId,
      category: ServiceCategory.gasfiteria,
      title: 'Gasfitero a domicilio',
      description: 'Arreglo fugas y griferías.',
      lat: -5.1950,
      lng: -80.6320,
    );
    final db = await local.database;
    // El servicio ya llegó al servidor: solo la calificación será pendiente.
    await db.update('local_services', {'sync_status': 'SYNCED'});
    await db.delete('sync_outbox');
    service = LocalServiceModel.fromSqlite((await db.query('local_services')).single);
    phase = ValueNotifier(SyncPhase.idle);
  });
  tearDown(() => local.close());

  Future<void> open(WidgetTester tester, {String? userId}) async {
    tester.view.physicalSize = const Size(800, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.day(),
        home: Scaffold(
          body: ServiceDetailSheet(
            service: service,
            tenantId: tenantId,
            userId: userId ?? neighborId,
            centerLat: -5.19449,
            centerLng: -80.63282,
            syncPhase: phase,
          ),
        ),
      ),
    );
    // Espera a que termine de cargar (la base real puede tardar en equipos lentos).
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
      await tester.pump();
      if (find.text('Cargando calificaciones…').evaluate().isEmpty) break;
    }
    await tester.pumpAndSettle();
  }

  Future<void> tapAndWait(WidgetTester tester, Finder finder) async {
    await tester.runAsync(() async {
      await tester.tap(finder);
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('muestra el mini mapa, la descripción y el formulario', (tester) async {
    await open(tester);
    expect(find.byKey(ServiceDetailSheet.mapKey), findsOneWidget);
    expect(find.text('Arreglo fugas y griferías.'), findsOneWidget);
    expect(find.text('Califica este servicio'), findsOneWidget);
    expect(find.text('Todavía nadie calificó este servicio.'), findsOneWidget);
  });

  testWidgets('calificar sin internet guarda PENDING y pasa a Sincronizado', (tester) async {
    final handle = tester.ensureSemantics();
    await open(tester);

    await tester.tap(find.bySemanticsLabel('4 estrellas'));
    await tester.pump();
    await tester.enterText(find.byKey(ServiceDetailSheet.commentKey), 'Muy buen trabajo');
    await tester.pump();
    await tapAndWait(tester, find.byKey(ServiceDetailSheet.saveKey));

    expect(find.text('Pendiente'), findsWidgets);
    final rows = await tester.runAsync(
      () async => (await local.database).query('neighbor_endorsements'),
    );
    expect(rows!.single['rating'], 4);
    expect(rows.single['short_comment'], 'Muy buen trabajo');
    expect(rows.single['sync_status'], 'PENDING');

    // Vuelve la señal: el servidor confirma y la pantalla se actualiza sola.
    await tester.runAsync(() async {
      await (await local.database).update(
        'neighbor_endorsements',
        {'sync_status': 'SYNCED'},
      );
      phase.value = SyncPhase.syncing;
      phase.value = SyncPhase.idle;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    expect(find.text('Pendiente'), findsNothing);
    expect(find.text('Sincronizado'), findsWidgets);
    handle.dispose();
  });

  testWidgets('tocar la misma estrella quita la calificación', (tester) async {
    final handle = tester.ensureSemantics();
    await open(tester);

    await tester.tap(find.bySemanticsLabel('4 estrellas'));
    await tester.pump();
    await tapAndWait(tester, find.byKey(ServiceDetailSheet.saveKey));

    await tapAndWait(tester, find.bySemanticsLabel('4 estrellas'));
    final rows = await tester.runAsync(
      () async => (await local.database).query('neighbor_endorsements'),
    );
    expect(rows!.single['is_deleted'], 1);
    expect(rows.single['sync_status'], 'PENDING');
    expect(find.text('Todavía nadie calificó este servicio.'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('el dueño del servicio no puede calificarlo', (tester) async {
    await open(tester, userId: providerId);
    expect(find.text('Califica este servicio'), findsNothing);
    expect(
      find.text('Este es tu servicio. Tus vecinos pueden calificarlo.'),
      findsOneWidget,
    );
  });

  testWidgets('cumple áreas táctiles, etiquetas y contraste', (tester) async {
    final handle = tester.ensureSemantics();
    await open(tester);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });
}
