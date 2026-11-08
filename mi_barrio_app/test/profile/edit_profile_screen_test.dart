import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_barrio_app/core/barrio_context/tenant_session.dart';
import 'package:mi_barrio_app/core/database_sqlite/sqlite_database.dart';
import 'package:mi_barrio_app/core/ui_kit/app_theme.dart';
import 'package:mi_barrio_app/features/profile_me/data/profile_local_storage.dart';
import 'package:mi_barrio_app/features/profile_me/presentation/screens/edit_profile_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  final local = LocalDatabase.instance;
  final session = TenantSession.instance;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
  });

  setUp(() async {
    await local.resetForTesting(path: inMemoryDatabasePath);
    await ProfileLocalStorage().saveProfile(
      userId: session.userId,
      tenantId: session.tenantId,
      fullName: 'Rosa Quispe',
      homeLat: session.centerLat,
      homeLng: session.centerLng,
    );
    // El perfil inicial no cuenta como cambio pendiente de la pantalla.
    await (await local.database).delete('sync_outbox');
  });
  tearDown(() => local.close());

  Future<void> open(WidgetTester tester) async {
    // Pantalla alta para que el formulario completo (y el botón) quepa sin scroll.
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.day(), home: const EditProfileScreen()));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();
  }

  FilledButton saveButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byKey(EditProfileScreen.saveButtonKey));

  Finder field(String label) => find.widgetWithText(TextField, label);

  testWidgets('"Guardar cambios" empieza deshabilitado y se habilita al editar', (tester) async {
    await open(tester);
    expect(find.text('Rosa Quispe'), findsOneWidget);
    expect(saveButton(tester).onPressed, isNull);

    await tester.enterText(field('WhatsApp (opcional)'), '+51 987 654 321');
    await tester.pump();
    expect(saveButton(tester).onPressed, isNotNull);

    await tester.enterText(field('WhatsApp (opcional)'), '');
    await tester.pump();
    expect(saveButton(tester).onPressed, isNull, reason: 'volver al valor guardado no es un cambio');
  });

  testWidgets('guarda redes en SQLite como PENDING y encola el cambio', (tester) async {
    await open(tester);
    await tester.enterText(field('WhatsApp (opcional)'), '+51 987 654 321');
    await tester.enterText(field('Instagram (https://…)'), 'https://instagram.com/rosa');
    await tester.pump();
    await tester.ensureVisible(find.byKey(EditProfileScreen.saveButtonKey));
    await tester.runAsync(() async {
      await tester.tap(find.byKey(EditProfileScreen.saveButtonKey));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();

    final rows = await tester.runAsync(() async => (await local.database).query('users'));
    expect(rows!.single['whatsapp'], '+51 987 654 321');
    expect(rows.single['instagram_url'], 'https://instagram.com/rosa');
    expect(rows.single['sync_status'], 'PENDING');
    final outbox = await tester.runAsync(() async => (await local.database).query('sync_outbox'));
    final payload = jsonDecode(outbox!.single['payload_json'] as String) as Map;
    expect(payload['whatsapp'], '+51 987 654 321');
    expect(payload.containsKey('role'), isFalse, reason: 'el rol nunca viaja desde el perfil');
    expect(saveButton(tester).onPressed, isNull, reason: 'ya no hay cambios sin guardar');
  });

  testWidgets('un WhatsApp inválido muestra un mensaje humano y no guarda', (tester) async {
    await open(tester);
    await tester.enterText(field('WhatsApp (opcional)'), 'llámame');
    await tester.pump();
    await tester.ensureVisible(find.byKey(EditProfileScreen.saveButtonKey));
    await tester.runAsync(() async {
      await tester.tap(find.byKey(EditProfileScreen.saveButtonKey));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('solo números'), findsOneWidget);
    final outbox = await tester.runAsync(() async => (await local.database).query('sync_outbox'));
    expect(outbox, isEmpty);
  });

  Future<void> tapSave(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(EditProfileScreen.saveButtonKey));
    await tester.runAsync(() async {
      await tester.tap(find.byKey(EditProfileScreen.saveButtonKey));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();
  }

  testWidgets('guarda el correo de contacto y lo envía como email_contacto', (tester) async {
    await open(tester);
    await tester.enterText(field('Correo de contacto (opcional)'), 'rosa.contacto@correo.com');
    await tester.pump();
    await tapSave(tester);

    final rows = await tester.runAsync(() async => (await local.database).query('users'));
    expect(rows!.single['email_contacto'], 'rosa.contacto@correo.com');
    final outbox = await tester.runAsync(() async => (await local.database).query('sync_outbox'));
    final payload = jsonDecode(outbox!.single['payload_json'] as String) as Map;
    expect(payload['email_contacto'], 'rosa.contacto@correo.com');

    // Al reabrir la pantalla, el correo sigue ahí.
    await open(tester);
    expect(find.text('rosa.contacto@correo.com'), findsOneWidget);
  });

  testWidgets('un correo de contacto inválido muestra un mensaje humano y no guarda', (tester) async {
    await open(tester);
    await tester.enterText(field('Correo de contacto (opcional)'), 'rosa.correo');
    await tester.pump();
    await tapSave(tester);
    expect(find.textContaining('correo de contacto'), findsOneWidget);
    final outbox = await tester.runAsync(() async => (await local.database).query('sync_outbox'));
    expect(outbox, isEmpty);
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
