import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_barrio_app/core/barrio_context/tenant_session.dart';
import 'package:mi_barrio_app/core/ui_kit/app_theme.dart';
import 'package:mi_barrio_app/core/ui_kit/main_navigation_shell.dart';
import 'package:mi_barrio_app/core/ui_kit/quick_publish_fab.dart';
import 'package:mi_barrio_app/features/emergency_support/domain/entities/vulnerable_report_entity.dart';
import 'package:mi_barrio_app/features/emergency_support/presentation/providers/emergency_provider.dart';
import 'package:mi_barrio_app/features/emergency_support/presentation/screens/emergency_map_screen.dart';
import 'package:mi_barrio_app/features/emergency_support/presentation/screens/humanitarian_board_screen.dart';
import 'package:mi_barrio_app/features/emergency_support/presentation/widgets/sos_sheet.dart';

const _lat = -5.1945; // centro de Piura
const _lng = -80.6328;

VulnerableReport _report(String id, String urgency, {double dLat = 0, String? reporter, String? updatedAt}) {
  return VulnerableReport(
    id: id,
    tenantId: TenantSession.instance.tenantId,
    reporterUserId: reporter ?? 'otro-vecino',
    urgencyLevel: urgency,
    vulnerabilityType: VulnerabilityType.adultoMayorSolo,
    description: 'Reporte $id',
    lat: _lat + dLat,
    lng: _lng,
    updatedAt: updatedAt ?? '2026-11-07T15:00:00Z',
  );
}

Widget _app(Widget child, {bool emergency = true}) => MaterialApp(
  theme: AppTheme.of(isEmergency: emergency),
  home: Scaffold(body: child),
);

double _y(WidgetTester tester, String id) =>
    tester.getTopLeft(find.byKey(ValueKey('help_report_$id'))).dy;

void main() {
  late InMemoryEmergencyRepository repo;

  setUp(() {
    TenantSession.instance.clearAuthenticatedUser();
    repo = InMemoryEmergencyRepository();
    EmergencyReports.use(repo);
    HelpLocator.resolve = () async => const HelpLocation(lat: _lat, lng: _lng, fromGps: true);
  });

  group('Flujo SOS en 3 clics', () {
    testWidgets('botón → tipo → enviar guarda el pedido con urgencia sugerida', (tester) async {
      await tester.pumpWidget(_app(Builder(
        builder: (context) => Center(
          child: FilledButton(onPressed: () => showSosSheet(context), child: const Text('Pedir ayuda')),
        ),
      )));

      await tester.tap(find.text('Pedir ayuda')); // clic 1
      await tester.pumpAndSettle();
      final send = find.byKey(SosSheet.sendButtonKey);
      expect(tester.widget<FilledButton>(send).onPressed, isNull, reason: 'sin tipo no se puede enviar');

      await tester.tap(find.byKey(const ValueKey('sos_type_ATENCION_MEDICA'))); // clic 2
      await tester.pumpAndSettle();
      await tester.ensureVisible(send);
      await tester.tap(send); // clic 3
      await tester.pumpAndSettle();

      final saved = await repo.activeReports(TenantSession.instance.tenantId);
      expect(saved, hasLength(1));
      expect(saved.single.vulnerabilityType, VulnerabilityType.atencionMedica);
      expect(saved.single.urgencyLevel, UrgencyLevel.critica);
      expect(saved.single.isPending, isTrue);
      expect(saved.single.lat, _lat);
      expect(find.textContaining('Se enviará apenas haya señal'), findsOneWidget);
    });

    testWidgets('sin GPS usa el centro del barrio y sigue funcionando', (tester) async {
      HelpLocator.resolve = () async => HelpLocation(
        lat: TenantSession.instance.centerLat,
        lng: TenantSession.instance.centerLng,
        fromGps: false,
      );
      await tester.pumpWidget(_app(Builder(
        builder: (context) => Center(
          child: FilledButton(onPressed: () => showSosSheet(context), child: const Text('Abrir')),
        ),
      )));
      await tester.tap(find.text('Abrir'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sos_type_FALTA_SUMINISTROS')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(SosSheet.sendButtonKey));
      await tester.tap(find.byKey(SosSheet.sendButtonKey));
      await tester.pumpAndSettle();

      final saved = (await repo.activeReports(TenantSession.instance.tenantId)).single;
      expect(saved.urgencyLevel, UrgencyLevel.media);
      expect(saved.lat, TenantSession.instance.centerLat);
    });
  });

  group('Tablero humanitario', () {
    testWidgets('ordena por urgencia: Crítica, Alta, Media', (tester) async {
      EmergencyReports.use(InMemoryEmergencyRepository(seed: [
        _report('m', UrgencyLevel.media),
        _report('c', UrgencyLevel.critica),
        _report('a', UrgencyLevel.alta),
      ]));
      await tester.pumpWidget(_app(const HumanitarianBoardScreen(isEmergencyMode: true)));
      await tester.pumpAndSettle();

      expect(_y(tester, 'c'), lessThan(_y(tester, 'a')));
      expect(_y(tester, 'a'), lessThan(_y(tester, 'm')));
      // La urgencia también se dice con texto, no solo con color.
      expect(find.text('Urgencia Crítica'), findsOneWidget);
    });

    testWidgets('"Voy en camino" cambia el estado; en mi propio pedido no aparece', (tester) async {
      repo = InMemoryEmergencyRepository(seed: [
        _report('ajeno', UrgencyLevel.alta),
        _report('mio', UrgencyLevel.media, reporter: TenantSession.instance.userId),
      ]);
      EmergencyReports.use(repo);
      await tester.pumpWidget(_app(const HumanitarianBoardScreen(isEmergencyMode: true)));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('offer_help_mio')), findsNothing);
      expect(find.textContaining('Tu pedido'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('offer_help_ajeno')));
      await tester.pumpAndSettle();
      final updated = (await repo.activeReports(TenantSession.instance.tenantId)).firstWhere((r) => r.id == 'ajeno');
      expect(updated.status, ReportStatus.vecinosEnCamino);
      expect(updated.helperUserId, TenantSession.instance.userId);
      expect(find.text('Vecinos en camino'), findsOneWidget);
      expect(find.byKey(const ValueKey('offer_help_ajeno')), findsNothing);
    });

    testWidgets('sin pedidos muestra un mensaje claro', (tester) async {
      await tester.pumpWidget(_app(const HumanitarianBoardScreen(isEmergencyMode: true)));
      await tester.pumpAndSettle();
      expect(find.textContaining('Nadie ha pedido ayuda'), findsOneWidget);
    });
  });

  group('Mapa en modo lista por cercanía', () {
    testWidgets('ordena del más cercano al más lejano y muestra la distancia', (tester) async {
      EmergencyReports.use(InMemoryEmergencyRepository(seed: [
        _report('lejos', UrgencyLevel.critica, dLat: 0.02), // ~2,2 km
        _report('cerca', UrgencyLevel.media, dLat: 0.003), // ~330 m
      ]));
      await tester.pumpWidget(_app(const EmergencyMapScreen(startInList: true)));
      await tester.pumpAndSettle();

      expect(find.text('Mapa de ayuda'), findsOneWidget);
      expect(find.text('Distancias desde tu ubicación actual.'), findsOneWidget);
      expect(_y(tester, 'cerca'), lessThan(_y(tester, 'lejos')));
      expect(find.text('a 334 m'), findsOneWidget);

      await tester.tap(find.byKey(EmergencyMapScreen.urgencyKey));
      await tester.pumpAndSettle();
      expect(_y(tester, 'lejos'), lessThan(_y(tester, 'cerca')), reason: 'por urgencia, la crítica va primero');
    });

    testWidgets('sin GPS avisa que mide desde el centro del barrio', (tester) async {
      HelpLocator.resolve = () async => const HelpLocation(lat: _lat, lng: _lng, fromGps: false);
      await tester.pumpWidget(_app(const EmergencyMapScreen(startInList: true)));
      await tester.pumpAndSettle();
      expect(find.text('Sin GPS: distancias desde el centro del barrio.'), findsOneWidget);
    });

    testWidgets('un SOS nuevo aparece en el mapa sin recargar', (tester) async {
      await tester.pumpWidget(_app(const EmergencyMapScreen(startInList: true)));
      await tester.pumpAndSettle();
      await repo.createSos(
        tenantId: TenantSession.instance.tenantId,
        reporterUserId: 'otro',
        vulnerabilityType: VulnerabilityType.viviendaAfectada,
        urgencyLevel: UrgencyLevel.alta,
        description: 'Se cayó el techo',
        lat: _lat,
        lng: _lng,
      );
      await tester.pumpAndSettle();
      expect(find.text('Se cayó el techo'), findsOneWidget);
    });
  });

  group('Estilo de emergencia en la navegación', () {
    testWidgets('franja + chip "Emergencia" solo en modo emergencia', (tester) async {
      await tester.pumpWidget(ProviderScope(child: MaterialApp(
        theme: AppTheme.emergency(),
        home: const MainNavigationShell(isEmergencyMode: true),
      )));
      await tester.pump();
      expect(find.byKey(MainNavigationShell.emergencyChipKey), findsOneWidget);
      expect(find.byKey(MainNavigationShell.emergencyBannerKey), findsOneWidget);

      await tester.pumpWidget(ProviderScope(child: MaterialApp(
        theme: AppTheme.day(),
        home: const MainNavigationShell(isEmergencyMode: false),
      )));
      await tester.pump();
      expect(find.byKey(MainNavigationShell.emergencyChipKey), findsNothing);
    });

    testWidgets('en emergencia, "Pedir ayuda" abre el SOS y luego muestra el Mapa', (tester) async {
      await tester.pumpWidget(ProviderScope(child: MaterialApp(
        theme: AppTheme.emergency(),
        home: Builder(
          builder: (context) => MainNavigationShell(
            isEmergencyMode: true,
            onPublish: () => showSosSheet(context),
          ),
        ),
      )));
      await tester.pump();
      expect(find.text('Ayuda'), findsOneWidget);

      await tester.tap(find.byKey(QuickPublishFab.fabKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sos_type_MOVILIDAD_REDUCIDA')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(SosSheet.sendButtonKey));
      await tester.tap(find.byKey(SosSheet.sendButtonKey));
      await tester.pumpAndSettle();

      final nav = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(nav.selectedIndex, MainNavigationShell.mapaTabIndex);
      expect(find.text('Mapa de ayuda'), findsOneWidget);
    });
  });

  group('Accesibilidad', () {
    for (final emergency in [true, false]) {
      testWidgets('tablero (${emergency ? 'emergencia' : 'normal'}): toque 48dp, etiquetas y contraste', (tester) async {
        final handle = tester.ensureSemantics();
        EmergencyReports.use(InMemoryEmergencyRepository(seed: [
          _report('c', UrgencyLevel.critica),
          _report('a', UrgencyLevel.alta),
          _report('m', UrgencyLevel.media, reporter: TenantSession.instance.userId),
        ]));
        await tester.pumpWidget(_app(const EmergencyMapScreen(startInList: true), emergency: emergency));
        await tester.pumpAndSettle();
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
      });
    }

    testWidgets('hoja SOS: toque 48dp, etiquetas y contraste', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_app(const SingleChildScrollView(child: SosSheet())));
      await tester.tap(find.byKey(const ValueKey('sos_type_ADULTO_MAYOR_SOLO')));
      await tester.pumpAndSettle();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
    });

    testWidgets('texto del sistema al 200% sin desbordes', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 3;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      EmergencyReports.use(InMemoryEmergencyRepository(seed: [
        _report('c', UrgencyLevel.critica, dLat: 0.01),
        _report('m', UrgencyLevel.media, reporter: TenantSession.instance.userId),
      ]));
      await tester.pumpWidget(_app(const EmergencyMapScreen(startInList: true)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(_app(const SingleChildScrollView(child: SosSheet())));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
