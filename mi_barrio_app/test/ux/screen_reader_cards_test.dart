import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_barrio_app/core/ui_kit/app_theme.dart';
import 'package:mi_barrio_app/features/proximity_services/presentation/widgets/service_card.dart';

void main() {
  testWidgets('tarjeta de servicio: el lector la lee junta, como un botón', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var opened = 0;
    var endorsed = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.day(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: ServiceCard(
              title: 'Gasfitero 24 horas',
              categoryLabel: 'Gasfitería',
              categoryIcon: Icons.plumbing_rounded,
              description: 'Arreglo fugas y caños',
              endorsementsCount: 2,
              isEndorsed: false,
              onTap: () => opened++,
              onEndorse: () => endorsed++,
            ),
          ),
        ),
      ),
    );

    final node = tester.getSemantics(find.text('Gasfitero 24 horas'));
    expect(node.label, contains('Gasfitería'));
    expect(node.label, contains('Gasfitero 24 horas'));
    expect(node.label, contains('Arreglo fugas'));
    expect(node.hint, 'Toca dos veces para ver el detalle');
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);

    // Doble toque del lector = abrir el detalle.
    node.owner!.performAction(
      node.id,
      SemanticsAction.tap,
    );
    expect(opened, 1);
    expect(endorsed, 0, reason: 'el Visto Bueno es un botón aparte');

    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
  });
}
