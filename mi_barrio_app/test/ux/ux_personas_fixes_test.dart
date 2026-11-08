import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mi_barrio_app/core/barrio_context/emergency_mode_provider.dart';
import 'package:mi_barrio_app/core/barrio_context/tenant_session.dart';
import 'package:mi_barrio_app/core/database_sqlite/local_id.dart';
import 'package:mi_barrio_app/core/database_sqlite/sqlite_database.dart';
import 'package:mi_barrio_app/core/database_sqlite/sqlite_tables.dart';
import 'package:mi_barrio_app/core/sync_manager/sync_coordinator.dart';
import 'package:mi_barrio_app/core/sync_manager/sync_worker.dart';
import 'package:mi_barrio_app/core/ui_kit/app_theme.dart';
import 'package:mi_barrio_app/features/emergency_support/domain/entities/vulnerable_report_entity.dart';
import 'package:mi_barrio_app/features/proximity_services/data/datasources/services_sqlite_ds.dart';
import 'package:mi_barrio_app/features/proximity_services/data/models/service_model.dart';
import 'package:mi_barrio_app/features/proximity_services/presentation/screens/services_directory_screen.dart';
import 'package:mi_barrio_app/features/proximity_services/presentation/widgets/service_detail_sheet.dart';
import 'package:mi_barrio_app/features/solidarity_network/data/datasources/solidarity_sqlite_ds.dart';
import 'package:mi_barrio_app/features/solidarity_network/data/models/solidarity_post_model.dart';
import 'package:mi_barrio_app/features/solidarity_network/presentation/screens/apoyo_screen.dart';
import 'package:mi_barrio_app/features/solidarity_network/presentation/screens/collaborative_wall_screen.dart';
import 'package:mi_barrio_app/shared/contact_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Arreglos de la base de pruebas por personas (docs/PRUEBAS_UX_PERSONAS.md).
void main() {
  final local = LocalDatabase.instance;
  final tenant = LocalId.generate();
  final me = LocalId.generate();
  final provider = LocalId.generate();
  const lat = -5.1945;
  const lng = -80.6328;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
  });
  setUp(() async {
    await local.resetForTesting(path: inMemoryDatabasePath);
    TenantSession.instance.applyAuthenticatedUser(
      authenticatedTenantId: tenant, authenticatedUserId: me, authenticatedTenantName: 'Barrio',
      authenticatedRole: 'VECINO', authenticatedCenterLat: lat, authenticatedCenterLng: lng);
    EmergencyModeProvider.instance.resetForTesting();
  });
  tearDown(() async {
    EmergencyModeProvider.instance.resetForTesting();
    await local.close();
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump();
    }
  }

  Widget app(Widget home, {double textScale = 1, bool emergency = false}) => MaterialApp(
        theme: AppTheme.of(isEmergency: emergency),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: home,
      );

  // ───────── Hallazgo 1: contactar al comerciante ─────────
  group('Contacto del comerciante (Llamar / WhatsApp)', () {
    test('números peruanos: tel con +51 y WhatsApp internacional', () {
      expect(ContactLauncher.telUri('+51 900 000 001').toString(), 'tel:+51900000001');
      expect(ContactLauncher.whatsappUri('987 654 321').toString(), 'https://wa.me/51987654321');
      expect(ContactLauncher.whatsappUri('+51 987-654-321').toString(), 'https://wa.me/51987654321');
      expect(ContactLauncher.whatsappUri('0051987654321').toString(), 'https://wa.me/51987654321');
      expect(ContactLauncher.isDialable(''), isFalse);
      expect(ContactLauncher.isDialable('  '), isFalse);
    });

    test('el pull guarda el contacto que manda el servidor (SQLite v7)', () async {
      final client = MockClient((_) async => http.Response(
            jsonEncode({
              'server_timestamp': '2026-11-07T20:00:00Z',
              'delta': {
                'local_services': [
                  {
                    'id': 'svc-1', 'tenant_id': tenant, 'provider_user_id': provider,
                    'category': 'GASFITERIA', 'title': 'Don Pedro', 'description': '',
                    'is_available_in_emergency': false, 'lat': lat, 'lng': lng, 'is_deleted': false,
                    'updated_at': '2026-11-07T10:00:00Z', 'server_updated_at': '2026-11-07T10:00:00Z',
                    'rating_avg': 4.8, 'contact_phone': '+51900000001', 'contact_whatsapp': '987654321',
                  },
                ],
              },
            }),
            200,
          ));
      expect((await SyncWorker(baseUrl: 'http://api', client: client).pullRemoteChanges(tenant)).success, isTrue);
      final svc = (await ServicesSqliteDatasource().getServices(tenant)).single;
      expect(svc.contactPhone, '+51900000001');
      expect(svc.contactWhatsapp, '987654321');
      expect(svc.toSyncPayload().containsKey('contact_phone'), isFalse, reason: 'el teléfono no lo envía');
    });

    test('un teléfono en v6 sube a v7 sin perder sus servicios', () async {
      final dir = await Directory.systemTemp.createTemp('mi_barrio_v6');
      final path = '${dir.path}${Platform.pathSeparator}v6.db';
      addTearDown(() async {
        await local.close();
        await dir.delete(recursive: true);
      });
      const v6Services = '''
        CREATE TABLE local_services (
          id TEXT PRIMARY KEY, tenant_id TEXT NOT NULL, provider_user_id TEXT NOT NULL,
          category TEXT NOT NULL, title TEXT NOT NULL, description TEXT NOT NULL DEFAULT '',
          is_available_in_emergency INTEGER NOT NULL DEFAULT 0, endorsements_count INTEGER NOT NULL DEFAULT 0,
          rating_avg REAL, publisher_type TEXT, publisher_name TEXT, lat REAL NOT NULL, lng REAL NOT NULL,
          is_deleted INTEGER NOT NULL DEFAULT 0, updated_at TEXT NOT NULL, sync_status TEXT NOT NULL DEFAULT 'SYNCED')''';
      final v6 = await databaseFactoryFfi.openDatabase(path,
          options: OpenDatabaseOptions(version: 6, onCreate: (d, _) async {
            await d.execute(v6Services); // la tabla vieja, sin columnas de contacto
            for (final sql in SqliteTables.createAll) {
              if (sql == SqliteTables.createLocalServices) continue;
              await d.execute(sql);
            }
          }));
      await v6.insert('local_services', {
        'id': 'viejo', 'tenant_id': tenant, 'provider_user_id': provider, 'category': 'CLASES',
        'title': 'Profe Carmen', 'lat': lat, 'lng': lng, 'updated_at': '2026-11-07T10:00:00Z',
      });
      await v6.insert('sync_state', {'tenant_id': tenant, 'last_pulled_at': '2026-11-07T12:00:00Z'});
      await v6.close();

      await local.resetForTesting(path: path);
      final svc = (await ServicesSqliteDatasource().getServices(tenant)).single;
      expect(svc.title, 'Profe Carmen');
      expect(svc.contactPhone, isNull);
      expect(await (await local.database).getVersion(), SqliteTables.schemaVersion);
      // Se olvidó el cursor: el próximo pull vuelve a bajar todo, ya con el contacto.
      expect(await (await local.database).query('sync_state'), isEmpty);
    });

    testWidgets('el detalle de un servicio AJENO muestra Llamar y WhatsApp', (tester) async {
      late LocalServiceModel service;
      await tester.runAsync(() async {
        service = await ServicesSqliteDatasource().insertService(
            tenantId: tenant, providerUserId: provider, category: ServiceCategory.gasfiteria,
            title: 'Don Pedro', publisherName: 'Don Pedro', lat: lat, lng: lng);
        await (await local.database).update('local_services',
            {'contact_phone': '+51900000001', 'contact_whatsapp': '987654321', 'sync_status': 'SYNCED'});
        service = (await ServicesSqliteDatasource().getServices(tenant)).single;
      });
      tester.view.physicalSize = const Size(800, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(Scaffold(
        body: ServiceDetailSheet(service: service, tenantId: tenant, userId: me,
            centerLat: lat, centerLng: lng, syncPhase: ValueNotifier(SyncPhase.idle)),
      )));
      await settle(tester);

      expect(find.textContaining('Todavía no hay un número'), findsNothing);
      expect(find.byKey(ServiceDetailSheet.callButtonKey), findsOneWidget);
      expect(find.byKey(ServiceDetailSheet.whatsappButtonKey), findsOneWidget);
      expect(find.bySemanticsLabel('Llamar a Don Pedro'), findsOneWidget);
    });
  });

  // ───────── Hallazgo 2: Publicar con letra grande ─────────
  group('Publicar con letra 2x (adulta mayor)', () {
    testWidgets('la pantalla de Apoyo se lee completa y sin errores', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(app(
        const ApoyoScreen(lat: lat, lng: lng),
        textScale: 2.0,
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      for (final label in ['Herramienta', 'Habilidad', 'Material', 'Soporte', 'Otro']) {
        final text = find.text(label);
        // La lista se arma a medida que se baja: se desplaza hasta verla.
        await tester.scrollUntilVisible(text, 150, scrollable: find.byType(Scrollable).first);
        expect(text, findsOneWidget, reason: label);
        final paragraph = tester.renderObject<RenderParagraph>(text);
        expect(paragraph.didExceedMaxLines, isFalse, reason: '"$label" no se corta');
      }
      // "Publicar" siempre a la vista, aunque la pantalla sea larga.
      expect(find.byKey(ApoyoScreen.publishKey).hitTestable(), findsOneWidget);
    });
  });

  // ───────── Hallazgo 5: lenguaje simple ─────────
  test('Pedir ayuda usa palabras simples (mismos valores para el servidor)', () {
    expect(VulnerabilityType.labels[VulnerabilityType.atencionMedica], 'Alguien está enfermo o herido');
    expect(VulnerabilityType.labels[VulnerabilityType.movilidadReducida], 'No puede caminar o moverse');
    expect(VulnerabilityType.labels[VulnerabilityType.viviendaAfectada], 'Se dañó la casa');
    expect(VulnerabilityType.atencionMedica, 'ATENCION_MEDICA');
  });

  // ───────── Hallazgo 4: lo urgente primero ─────────
  testWidgets('en emergencia el podio aparece ANTES del buscador', (tester) async {
    await tester.runAsync(() async {
      for (var i = 0; i < 4; i++) {
        await ServicesSqliteDatasource().insertService(
            tenantId: tenant, providerUserId: provider, category: ServiceCategory.gasfiteria,
            title: 'Servicio $i', lat: lat, lng: lng, isAvailableInEmergency: true);
      }
    });
    await EmergencyModeProvider.instance.setTenantFlag(true);
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(Scaffold(body: ServicesDirectoryScreen(tenantId: tenant, userId: me)), emergency: true));
    await settle(tester);

    final podium = find.byWidgetPredicate((w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith('podium_service_'));
    expect(podium, findsNWidgets(3));
    final firstPodium = tester.getTopLeft(podium.first).dy;
    final search = tester.getTopLeft(find.byKey(const ValueKey('services_search'))).dy;
    expect(firstPodium, lessThan(search));
    expect(find.text('Servicio 3'), findsOneWidget, reason: 'no se repite abajo');
    expect(find.bySemanticsLabel(RegExp('Prioridad 1 de 3')), findsWidgets);
  });

  // ───────── Hallazgos 5 y 6: muro sin ruido y con estado ─────────
  testWidgets('muro: "Sincronizado" ya no se repite y se ve si alguien ayuda', (tester) async {
    await tester.runAsync(() async {
      await (await local.database).insert(SolidarityPostModel.table, SolidarityPostModel(
        id: 'p1', tenantId: tenant, authorUserId: provider, flowType: SolidarityFlowType.solicitoAyuda,
        modality: SolidarityModality.recursoCritico, title: 'Agua para 3 familias',
        status: SolidarityStatus.enCoordinacion, lat: lat, lng: lng,
        updatedAt: '2026-11-07T10:00:00Z', syncStatus: SqliteTables.syncSynced).toSqlite());
      await SolidaritySqliteDatasource().publishInThreeClicks(
          tenantId: tenant, authorUserId: me, modality: SolidarityModality.prestamoHerramienta,
          title: 'Escalera', lat: lat, lng: lng);
    });
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(Scaffold(body: CollaborativeWallScreen(tenantId: tenant))));
    await settle(tester);

    expect(find.text('Sincronizado'), findsNothing);
    expect(find.text('Pendiente'), findsOneWidget, reason: 'solo lo que falta enviar');
    expect(find.text('Alguien ya está ayudando'), findsOneWidget);
  });
}
