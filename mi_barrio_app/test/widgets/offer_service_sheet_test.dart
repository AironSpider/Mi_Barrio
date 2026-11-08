import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_barrio_app/core/database_sqlite/local_id.dart';
import 'package:mi_barrio_app/core/database_sqlite/sqlite_database.dart';
import 'package:mi_barrio_app/core/ui_kit/app_theme.dart';
import 'package:mi_barrio_app/core/ui_kit/photo_picker.dart';
import 'package:mi_barrio_app/features/emergency_support/presentation/providers/emergency_provider.dart';
import 'package:mi_barrio_app/features/proximity_services/data/datasources/services_sqlite_ds.dart';
import 'package:mi_barrio_app/features/proximity_services/data/models/service_model.dart';
import 'package:mi_barrio_app/features/proximity_services/presentation/widgets/offer_service_sheet.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  final local = LocalDatabase.instance;
  final tenantId = LocalId.generate();
  final merchantId = LocalId.generate();
  late bool? published;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await local.resetForTesting(path: inMemoryDatabasePath);
    published = null;
    // GPS simulado: el formulario lo pide al abrir para ubicar el servicio.
    HelpLocator.resolve = () async => const HelpLocation(lat: -5.1950, lng: -80.6330, fromGps: true);
  });
  tearDown(() => local.close());

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.day(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () async {
                  published = await showOfferServiceSheet(
                    context,
                    tenantId: tenantId,
                    userId: merchantId,
                    profile: const MerchantProfile(
                      isMerchant: true,
                      publisherType: 'Emprendedor',
                      publisherName: 'Gas Ramos',
                    ),
                  );
                },
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
  }

  testWidgets('publicar es imposible hasta elegir rubro y escribir el título', (tester) async {
    await open(tester);
    FilledButton publish() =>
        tester.widget<FilledButton>(find.byKey(OfferServiceSheet.publishKey));
    expect(publish().onPressed, isNull);

    await tester.tap(find.text('Gasfitería'));
    await tester.pumpAndSettle();
    expect(publish().onPressed, isNull);

    await tester.enterText(find.byKey(OfferServiceSheet.titleKey), 'Gasfitero a domicilio');
    await tester.pump();
    expect(publish().onPressed, isNotNull);
  });

  testWidgets('en 3 pasos guarda el servicio como PENDING y lo encola', (tester) async {
    await open(tester);
    await tester.tap(find.text('Gasfitería')); // clic 2: rubro
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(OfferServiceSheet.titleKey), 'Gasfitero a domicilio');
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.byKey(OfferServiceSheet.publishKey)); // clic 3
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();

    expect(published, isTrue);
    final rows = await tester.runAsync(
      () async => (await local.database).query('local_services'),
    );
    expect(rows!.single['title'], 'Gasfitero a domicilio');
    expect(rows.single['category'], 'GASFITERIA');
    expect(rows.single['provider_user_id'], merchantId);
    expect(rows.single['publisher_name'], 'Gas Ramos');
    expect(rows.single['sync_status'], 'PENDING');
    final outbox = await tester.runAsync(
      () async => (await local.database).query('sync_outbox'),
    );
    final payload = jsonDecode(outbox!.single['payload_json'] as String) as Map;
    expect(payload['title'], 'Gasfitero a domicilio');
    expect(payload['is_available_in_emergency'], false);
  });

  testWidgets('cumple áreas táctiles, etiquetas y contraste', (tester) async {
    final handle = tester.ensureSemantics();
    await open(tester);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });

  Future<void> settleDb(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('servicio completo: rubro nuevo, precio, fotos y ubicación GPS', (tester) async {
    appPhotoPicker = (_) async => base64Decode(_png);
    addTearDown(() => appPhotoPicker = (_) async => null);
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('offer_category_ALBANILERIA')));
    await tester.pump();
    await tester.enterText(find.byKey(OfferServiceSheet.titleKey), 'Albañil con experiencia');
    await tester.enterText(find.byKey(OfferServiceSheet.priceKey), 'S/ 80 el día');
    await tester.ensureVisible(find.byKey(OfferServiceSheet.addPhotoKey));
    await tester.tap(find.byKey(OfferServiceSheet.addPhotoKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Elegir de la galería'));
    await tester.pumpAndSettle();
    expect(find.text('Fotos (1/4)'), findsOneWidget);

    await tester.ensureVisible(find.byKey(OfferServiceSheet.publishKey));
    await tester.tap(find.byKey(OfferServiceSheet.publishKey));
    await settleDb(tester);

    expect(published, isTrue);
    final row = (await tester.runAsync(() async => (await local.database).query('local_services')))!.single;
    expect(row['category'], 'ALBANILERIA');
    expect(row['price_text'], 'S/ 80 el día');
    expect(row['photo_count'], 1);
    expect(row['lat'], -5.1950, reason: 'ubicación del GPS');
    final payload = jsonDecode(
      (await tester.runAsync(() async => (await local.database).query('sync_outbox')))!.single['payload_json'] as String,
    ) as Map;
    expect(payload['price_text'], 'S/ 80 el día');
    expect((payload['photos'] as List).length, 1);
  });

  testWidgets('editar un servicio publicado y luego retirarlo', (tester) async {
    final ds = ServicesSqliteDatasource();
    final svc = (await tester.runAsync(() => ds.insertService(
          tenantId: tenantId,
          providerUserId: merchantId,
          category: 'GASFITERIA',
          title: 'Gasfitero',
          lat: -5.19,
          lng: -80.63,
        )))!;
    await tester.runAsync(() async => (await local.database).delete('sync_outbox'));
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.day(),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () async => published = await showOfferServiceSheet(
                context,
                tenantId: tenantId,
                userId: merchantId,
                existing: svc,
              ),
              child: const Text('Editar'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Editar'));
    await settleDb(tester);
    expect(find.text('Editar servicio'), findsOneWidget);
    expect(find.text('Guardar cambios'), findsOneWidget);

    await tester.enterText(find.byKey(OfferServiceSheet.titleKey), 'Gasfitero 24 horas');
    await tester.enterText(find.byKey(OfferServiceSheet.priceKey), 'A tratar');
    await tester.ensureVisible(find.byKey(OfferServiceSheet.publishKey));
    await tester.tap(find.byKey(OfferServiceSheet.publishKey));
    await settleDb(tester);
    expect(published, isTrue);
    var row = (await tester.runAsync(() async => (await local.database).query('local_services')))!.single;
    expect(row['title'], 'Gasfitero 24 horas');
    expect(row['price_text'], 'A tratar');
    expect(row['id'], svc.id, reason: 'se edita el mismo servicio, no se crea otro');

    final edited = LocalServiceModel.fromSqlite(row);
    await tester.runAsync(() => ds.retireService(edited, merchantId));
    row = (await tester.runAsync(() async => (await local.database).query('local_services')))!.single;
    expect(row['is_deleted'], 1);
    expect(
      () => ds.retireService(edited, 'otro-vecino'),
      throwsArgumentError,
      reason: 'solo el dueño retira su servicio',
    );
  });
}

const _png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
