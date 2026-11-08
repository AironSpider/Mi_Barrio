import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_barrio_app/core/database_sqlite/sqlite_database.dart';
import 'package:mi_barrio_app/core/ui_kit/app_theme.dart';
import 'package:mi_barrio_app/features/solidarity_network/presentation/widgets/support_groups_section.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  const tenant = 'a1b2c3d4-e5f6-4a8b-9c0d-1e2f3a4b5c6d';
  const lat = -5.1945;
  const lng = -80.6328;
  final local = LocalDatabase.instance;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
  });
  setUp(() => local.resetForTesting(path: inMemoryDatabasePath));
  tearDown(() => local.close());

  Future<void> seed(WidgetTester tester) => tester.runAsync(() async {
        final db = await local.database;
        Future<void> add(String id, String name, String type,
            {double? glat, double? glng, String? phone, String? point, int active = 1, String t = tenant}) {
          return db.insert('support_groups', {
            'id': id,
            'tenant_id': t,
            'name': name,
            'group_type': type,
            'contact_phone': phone,
            'meeting_point': point,
            'lat': glat,
            'lng': glng,
            'is_active': active,
            'updated_at': '2026-11-07T10:00:00Z',
          });
        }

        await add('g1', 'Olla común', 'ALIMENTOS', glat: lat + 0.02, glng: lng, point: 'Comedor popular');
        await add('g2', 'Brigada de primeros auxilios', 'PRIMEROS_AUXILIOS',
            glat: lat + 0.001, glng: lng, phone: '+51 987 654 321');
        await add('g3', 'Grupo inactivo', 'RESCATE', active: 0);
        await add('g4', 'De otro barrio', 'ALBERGUE', t: 'b2c3d4e5-f6a7-4b8c-9d0e-2f3a4b5c6d7e');
      });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.of(isEmergency: true),
      home: const Scaffold(
        body: SingleChildScrollView(child: SupportGroupsSection(tenantId: tenant, lat: lat, lng: lng)),
      ),
    ));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();
  }

  testWidgets('muestra los grupos activos del barrio, del más cercano al más lejano', (tester) async {
    await seed(tester);
    await open(tester);

    expect(find.text('Grupos de apoyo'), findsOneWidget);
    expect(find.text('Grupo inactivo'), findsNothing);
    expect(find.text('De otro barrio'), findsNothing);
    final brigada = tester.getTopLeft(find.text('Brigada de primeros auxilios')).dy;
    final olla = tester.getTopLeft(find.text('Olla común')).dy;
    expect(brigada, lessThan(olla), reason: 'la brigada está más cerca');
    expect(find.text('Primeros auxilios'), findsOneWidget);
    expect(find.text('a 111 m'), findsOneWidget);
    expect(find.text('Comedor popular'), findsOneWidget);
  });

  testWidgets('"Copiar número" solo aparece si el grupo tiene teléfono y lo copia', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await seed(tester);
    await open(tester);

    expect(find.text('Copiar número'), findsOneWidget);
    await tester.tap(find.text('Copiar número'));
    await tester.pump();
    expect(copied, '+51 987 654 321');
  });

  testWidgets('sin grupos registrados avisa con un mensaje claro', (tester) async {
    await open(tester);
    expect(find.text('Grupos de apoyo: tu junta vecinal aún no registró ninguno.'), findsOneWidget);
  });

  testWidgets('accesible en emergencia: áreas táctiles, etiquetas y contraste', (tester) async {
    final handle = tester.ensureSemantics();
    await seed(tester);
    await open(tester);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });
}
