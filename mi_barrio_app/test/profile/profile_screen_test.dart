import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_barrio_app/core/barrio_context/tenant_session.dart';
import 'package:mi_barrio_app/core/database_sqlite/sqlite_database.dart';
import 'package:mi_barrio_app/core/ui_kit/app_theme.dart';
import 'package:mi_barrio_app/features/profile_me/data/profile_local_storage.dart';
import 'package:mi_barrio_app/features/profile_me/presentation/screens/profile_screen.dart';
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
      homeLat: -5.2,
      homeLng: -80.6,
      whatsapp: '+51 987 654 321',
      emailContacto: 'rosa@correo.com',
      instagramUrl: 'https://instagram.com/rosa',
      publisherType: 'BODEGA',
      publisherName: 'Bodega Rosita',
    );
    await (await local.database).delete('sync_outbox');
  });
  tearDown(() => local.close());

  testWidgets('"Guardar perfil" en Tú no borra redes, publicador ni ubicación', (tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(theme: AppTheme.day(), home: const Scaffold(body: ProfileScreen())),
    ));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Nombre y apellido'), 'Rosa Quispe Ruiz');
    await tester.pump();
    await tester.runAsync(() async {
      await tester.tap(find.text('Guardar perfil'));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();

    final rows = await tester.runAsync(() async => (await local.database).query('users'));
    final row = rows!.single;
    expect(row['full_name'], 'Rosa Quispe Ruiz');
    expect(row['whatsapp'], '+51 987 654 321');
    expect(row['email_contacto'], 'rosa@correo.com');
    expect(row['instagram_url'], 'https://instagram.com/rosa');
    expect(row['publisher_type'], 'BODEGA');
    expect(row['publisher_name'], 'Bodega Rosita');
    expect(row['home_lat'], -5.2);
    expect(row['home_lng'], -80.6);

    // Lo que viaja al servidor tampoco manda esos campos en null.
    final outbox = await tester.runAsync(() async => (await local.database).query('sync_outbox'));
    final payload = jsonDecode(outbox!.single['payload_json'] as String) as Map<String, dynamic>;
    expect(payload['whatsapp'], '+51 987 654 321');
    expect(payload['publisher_name'], 'Bodega Rosita');
  });
}
