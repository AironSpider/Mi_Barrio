import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_barrio_app/core/database_sqlite/local_id.dart';
import 'package:mi_barrio_app/core/database_sqlite/sqlite_database.dart';
import 'package:mi_barrio_app/core/ui_kit/app_theme.dart';
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
}
