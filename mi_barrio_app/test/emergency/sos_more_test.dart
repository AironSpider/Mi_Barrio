import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_barrio_app/core/barrio_context/tenant_session.dart';
import 'package:mi_barrio_app/core/ui_kit/app_theme.dart';
import 'package:mi_barrio_app/features/emergency_support/domain/entities/vulnerable_report_entity.dart';
import 'package:mi_barrio_app/features/emergency_support/presentation/providers/emergency_provider.dart';
import 'package:mi_barrio_app/features/emergency_support/presentation/widgets/sos_sheet.dart';

void main() {
  late InMemoryEmergencyRepository repo;

  setUp(() {
    repo = InMemoryEmergencyRepository();
    EmergencyReports.use(repo);
    HelpLocator.resolve = () async =>
        const HelpLocation(lat: -5.1945, lng: -80.6328, fromGps: true);
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.emergency(),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: FilledButton(
              onPressed: () => showSosSheet(context),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  testWidgets('lluvias e incendios: tipos nuevos, "Incendio" es crítico', (tester) async {
    await open(tester);
    for (final label in ['Se inundó o entró el agua', 'Hay fuego o humo', 'Quedamos atrapados o aislados', 'Otro']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(VulnerabilityType.defaultUrgency(VulnerabilityType.incendio), UrgencyLevel.critica);
    // "Enviar" siempre a la vista.
    expect(find.byKey(SosSheet.sendButtonKey).hitTestable(), findsOneWidget);
  });

  testWidgets('"Otro" pide escribir qué pasa (máx. 30) y guarda los datos de la urgencia', (tester) async {
    await open(tester);
    final send = find.byKey(SosSheet.sendButtonKey);
    await tester.tap(find.byKey(const ValueKey('sos_type_OTRO')));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(send).onPressed, isNull, reason: 'Otro sin texto no se envía');

    await tester.enterText(find.byKey(SosSheet.otherFieldKey), 'Cayó un poste con cables en mi calle hoy');
    await tester.pump();
    final typed = tester.widget<TextField>(find.byKey(SosSheet.otherFieldKey)).controller!.text;
    expect(typed.length, lessThanOrEqualTo(VulnerabilityType.maxOtherLabel));

    await tester.ensureVisible(find.byKey(SosSheet.peoplePlusKey));
    await tester.tap(find.byKey(SosSheet.peoplePlusKey));
    await tester.tap(find.byKey(SosSheet.peoplePlusKey));
    await tester.tap(find.byKey(const ValueKey('sos_injured_true')));
    await tester.ensureVisible(find.byKey(const ValueKey('sos_group_NINOS')));
    await tester.tap(find.byKey(const ValueKey('sos_group_NINOS')));
    await tester.enterText(find.byKey(SosSheet.phoneFieldKey), '999 888 777');
    await tester.pump();
    await tester.tap(send);
    await tester.pumpAndSettle();

    final saved = (await repo.activeReports(TenantSession.instance.tenantId)).single;
    expect(saved.vulnerabilityType, VulnerabilityType.otro);
    expect(saved.typeLabel, typed.trim());
    expect(saved.peopleCount, 2);
    expect(saved.hasInjured, isTrue);
    expect(saved.vulnerableGroups, [VulnerableGroup.ninos]);
    expect(saved.contactPhone, '999 888 777');
  });
}
