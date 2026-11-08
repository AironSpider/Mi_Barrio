import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_barrio_app/core/barrio_context/tenant_session.dart';
import 'package:mi_barrio_app/core/database_sqlite/sqlite_database.dart';
import 'package:mi_barrio_app/core/ui_kit/app_theme.dart';
import 'package:mi_barrio_app/features/profile_me/data/profile_local_storage.dart';
import 'package:mi_barrio_app/core/ui_kit/photo_picker.dart';
import 'package:mi_barrio_app/features/profile_me/presentation/screens/edit_profile_screen.dart';
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
      phone: '+51 987 654 321',
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

  /// Cada consulta a SQLite necesita tiempo real y luego un frame.
  Future<void> settleDb(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(theme: AppTheme.day(), home: const Scaffold(body: ProfileScreen())),
    ));
    await settleDb(tester);
  }

  testWidgets('muestra la información en modo lectura y un solo "Editar perfil"', (tester) async {
    await open(tester);
    expect(find.text('Rosa Quispe'), findsOneWidget);
    expect(find.text('+51 987 654 321'), findsNWidgets(2), reason: 'teléfono y WhatsApp');
    expect(find.text('rosa@correo.com'), findsOneWidget);
    expect(find.text('Negocio'), findsNothing, reason: 'un VECINO no ve la sección de negocio');
    expect(find.byType(TextField), findsNothing, reason: 'ya no hay un segundo formulario');
    expect(find.byKey(ProfileScreen.editKey), findsOneWidget);
    expect(find.text('Tu actividad'), findsOneWidget);
    expect(find.text('Mis mensajes'), findsOneWidget);

    await tester.tap(find.byKey(ProfileScreen.editKey));
    await settleDb(tester);
    expect(find.byType(EditProfileScreen), findsOneWidget);
  });

  testWidgets('cambiar la foto no borra redes, publicador ni ubicación', (tester) async {
    // PNG real de 1×1 px.
    appPhotoPicker = (_) async => base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==');
    addTearDown(() => appPhotoPicker = (_) async => null);
    await open(tester);
    await tester.tap(find.byKey(ProfileScreen.photoKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Elegir de la galería'));
    await settleDb(tester);

    final rows = await tester.runAsync(() async => (await local.database).query('users'));
    final row = rows!.single;
    expect(row['photo_b64'], isNotNull);
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
