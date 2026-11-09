import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_barrio_app/core/barrio_context/tenant_session.dart';
import 'package:mi_barrio_app/core/database_sqlite/sqlite_database.dart';
import 'package:mi_barrio_app/core/ui_kit/app_theme.dart';
import 'package:mi_barrio_app/features/emergency_support/domain/entities/vulnerable_report_entity.dart';
import 'package:mi_barrio_app/features/emergency_support/domain/neighbor_pins.dart';
import 'package:mi_barrio_app/features/emergency_support/presentation/providers/emergency_provider.dart';
import 'package:mi_barrio_app/features/emergency_support/presentation/screens/emergency_map_screen.dart';
import 'package:mi_barrio_app/features/emergency_support/presentation/widgets/help_report_card.dart';
import 'package:mi_barrio_app/features/emergency_support/presentation/widgets/neighbor_map.dart';
import 'package:mi_barrio_app/features/proximity_services/data/datasources/services_sqlite_ds.dart';
import 'package:mi_barrio_app/features/solidarity_network/data/datasources/solidarity_sqlite_ds.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _ana = 'aaaaaaaa-1111-4111-8111-111111111111';
const _beto = 'bbbbbbbb-2222-4222-8222-222222222222';

PinItem _item(
  String id,
  PinItemKind kind, {
  double lat = -5.19,
  double lng = -80.63,
  String at = '2026-11-07T10:00:00Z',
}) => PinItem(id: id, kind: kind, title: id, lat: lat, lng: lng, updatedAt: at);

void main() {
  group('NeighborPins (agrupar por persona)', () {
    test('un marcador por persona, con todas sus publicaciones', () {
      final pins = NeighborPins.build(
        itemsByUser: {
          _ana: [
            _item('favor', PinItemKind.favor),
            _item('servicio', PinItemKind.service),
          ],
          _beto: [_item('sos', PinItemKind.sos, lat: -5.2)],
        },
        myUserId: _beto,
        labels: {_ana: 'Bodega Ana'},
      );
      expect(pins, hasLength(2));
      final ana = pins.firstWhere((p) => p.userId == _ana);
      expect(ana.items, hasLength(2));
      expect(ana.label, 'Bodega Ana');
      expect(ana.mainKind, PinItemKind.service);
      final beto = pins.firstWhere((p) => p.userId == _beto);
      expect(beto.isMe, isTrue);
      expect(beto.label, 'Tú');
      expect(beto.mainKind, PinItemKind.sos);
    });

    test(
      'el SOS decide dónde se dibuja a la persona, aunque haya algo más nuevo',
      () {
        final pins = NeighborPins.build(
          itemsByUser: {
            _ana: [
              _item(
                'favor',
                PinItemKind.favor,
                lat: -5.10,
                at: '2026-11-07T12:00:00Z',
              ),
              _item(
                'sos',
                PinItemKind.sos,
                lat: -5.30,
                at: '2026-11-07T09:00:00Z',
              ),
            ],
          },
          myUserId: _beto,
        );
        expect(pins.single.lat, -5.30);
      },
    );

    test('dos personas en el mismo punto se separan para poder tocarlas', () {
      final pins = NeighborPins.build(
        itemsByUser: {
          _ana: [_item('a', PinItemKind.favor)],
          _beto: [_item('b', PinItemKind.favor)],
        },
        myUserId: 'otro',
      );
      final a = pins[0], b = pins[1];
      expect(
        (a.lat - b.lat).abs() + (a.lng - b.lng).abs(),
        greaterThan(0.0002),
      );
    });
  });

  group('Mapa de vecinos', () {
    final session = TenantSession.instance;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      await LocalDatabase.instance.resetForTesting(path: inMemoryDatabasePath);
      HelpLocator.resolve = () async => HelpLocation(
        lat: session.centerLat,
        lng: session.centerLng,
        fromGps: false,
      );
    });
    tearDown(() => LocalDatabase.instance.close());

    Future<InMemoryEmergencyRepository> seed(WidgetTester tester) async {
      final repo = InMemoryEmergencyRepository(
        seed: [
          VulnerableReport(
            id: 'sos-1',
            tenantId: session.tenantId,
            reporterUserId: _ana,
            urgencyLevel: UrgencyLevel.critica,
            vulnerabilityType: VulnerabilityType.atencionMedica,
            description: 'Fiebre alta',
            lat: session.centerLat + 0.001,
            lng: session.centerLng,
            updatedAt: '2026-11-07T10:00:00Z',
          ),
        ],
      );
      await tester.runAsync(() async {
        await SolidaritySqliteDatasource().publishInThreeClicks(
          tenantId: session.tenantId,
          authorUserId: _beto,
          modality: 'PRESTAMO_HERRAMIENTA',
          title: 'Presto escalera',
          flowType: 'OFREZCO_AYUDA',
          lat: session.centerLat,
          lng: session.centerLng,
        );
        await ServicesSqliteDatasource().insertService(
          tenantId: session.tenantId,
          providerUserId: _beto,
          category: 'GASFITERIA',
          title: 'Gasfitero Beto',
          lat: session.centerLat,
          lng: session.centerLng,
        );
      });
      return repo;
    }

    Future<void> pump(
      WidgetTester tester,
      InMemoryEmergencyRepository repo,
    ) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.day(),
          home: Scaffold(body: EmergencyMapScreen(repository: repo)),
        ),
      );
      // Cada consulta a SQLite necesita tiempo real y luego un frame.
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 60)),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    testWidgets('abre en vista Mapa con un marcador por vecino', (
      tester,
    ) async {
      final repo = await seed(tester);
      await pump(tester, repo);
      expect(find.text('Mapa de ayuda'), findsOneWidget);
      expect(find.byType(NeighborMap), findsOneWidget);
      expect(find.byKey(NeighborMap.pinKey(_ana)), findsOneWidget);
      expect(find.byKey(NeighborMap.pinKey(_beto)), findsOneWidget);
      expect(
        find.text('2 vecinos publicando. Toca uno para ver sus publicaciones.'),
        findsOneWidget,
      );
    });

    testWidgets('tocar un vecino muestra todas sus publicaciones', (
      tester,
    ) async {
      final repo = await seed(tester);
      await pump(tester, repo);
      await tester.tap(find.byKey(NeighborMap.pinKey(_beto)));
      await tester.pumpAndSettle();
      expect(find.text('2 publicaciones activas'), findsOneWidget);
      expect(find.text('Presto escalera'), findsOneWidget);
      expect(find.text('Gasfitero Beto'), findsOneWidget);
    });

    testWidgets(
      'en un SOS ajeno se puede decir "Voy en camino" desde el mapa',
      (tester) async {
        final repo = await seed(tester);
        await pump(tester, repo);
        await tester.tap(find.byKey(NeighborMap.pinKey(_ana)));
        await tester.pumpAndSettle();
        expect(find.text('Fiebre alta'), findsOneWidget);
        await tester.tap(find.text('Voy en camino'));
        await tester.pumpAndSettle();
        expect(find.text('Vas en camino. ¡Gracias!'), findsOneWidget);
        final updated = await repo.activeReports(session.tenantId);
        expect(updated.single.status, ReportStatus.vecinosEnCamino);
      },
    );

    testWidgets('el botón Lista muestra el tablero ordenado', (tester) async {
      final repo = await seed(tester);
      await pump(tester, repo);
      await tester.tap(find.byKey(EmergencyMapScreen.listViewKey));
      await tester.pumpAndSettle();
      expect(find.byType(NeighborMap), findsNothing);
      expect(find.byKey(EmergencyMapScreen.urgencyKey), findsOneWidget);
      expect(find.text('Fiebre alta'), findsOneWidget);
    });

    testWidgets('marcadores accesibles: 48 dp y con etiqueta', (tester) async {
      final handle = tester.ensureSemantics();
      final repo = await seed(tester);
      await pump(tester, repo);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      expect(
        find.bySemanticsLabel(RegExp('Vecino: Pide ayuda')),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  testWidgets('la tarjeta de urgencia permite ver el pin y las coordenadas', (
    tester,
  ) async {
    final report = VulnerableReport(
      id: 'sos-location',
      tenantId: TenantSession.instance.tenantId,
      reporterUserId: _ana,
      urgencyLevel: UrgencyLevel.critica,
      vulnerabilityType: VulnerabilityType.inundacion,
      description: 'El agua está entrando',
      lat: -5.19432,
      lng: -80.63145,
      updatedAt: '2026-11-07T10:00:00Z',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.day(),
        home: Scaffold(body: HelpReportCard(report: report)),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('report_location_sos-location')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ubicación de Se inundó o entró el agua'), findsOneWidget);
    expect(find.text('Latitud -5.19432 · Longitud -80.63145'), findsOneWidget);
    expect(find.byIcon(Icons.warning_rounded), findsOneWidget);
    expect(find.text('Abrir en mapas'), findsOneWidget);
  });
}
