import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_barrio_app/core/database_sqlite/local_id.dart';
import 'package:mi_barrio_app/core/ui_kit/app_theme.dart';
import 'package:mi_barrio_app/features/solidarity_network/data/models/solidarity_post_model.dart';
import 'package:mi_barrio_app/features/solidarity_network/presentation/widgets/favor_detail_sheet.dart';

void main() {
  final me = LocalId.generate();
  final other = LocalId.generate();

  SolidarityPostModel post({
    required String author,
    String status = SolidarityStatus.disponible,
  }) => SolidarityPostModel(
    id: LocalId.generate(),
    tenantId: LocalId.generate(),
    authorUserId: author,
    flowType: SolidarityFlowType.ofrezcoAyuda,
    modality: SolidarityModality.prestamoHerramienta,
    title: 'Presto escalera',
    description: 'Se recoge en mi casa.',
    status: status,
    lat: -5.1945,
    lng: -80.6328,
    updatedAt: DateTime.now().toUtc().toIso8601String(),
  );

  Future<void> open(
    WidgetTester tester,
    SolidarityPostModel p, {
    CoordinateFavorCallback? onCoordinate,
  }) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.day(),
        home: Scaffold(
          body: FavorDetailSheet(
            key: UniqueKey(),
            post: p,
            userId: me,
            onCoordinate: onCoordinate,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('un vecino puede coordinar un favor ajeno', (tester) async {
    var calls = 0;
    await open(tester, post(author: other), onCoordinate: (_) async => calls++);
    expect(find.byKey(FavorDetailSheet.coordinateKey), findsOneWidget);

    await tester.tap(find.byKey(FavorDetailSheet.coordinateKey));
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(find.byKey(FavorDetailSheet.coordinateKey), findsNothing);
    expect(find.textContaining('quedó en coordinación'), findsOneWidget);
  });

  testWidgets('el autor no ve el botón Coordinar', (tester) async {
    await open(tester, post(author: me), onCoordinate: (_) async {});
    expect(find.byKey(FavorDetailSheet.coordinateKey), findsNothing);
    expect(find.text('Este es tu favor.'), findsOneWidget);
  });

  testWidgets('un favor en coordinación o completado no se puede coordinar', (tester) async {
    await open(
      tester,
      post(author: other, status: SolidarityStatus.enCoordinacion),
      onCoordinate: (_) async {},
    );
    expect(find.byKey(FavorDetailSheet.coordinateKey), findsNothing);

    await open(
      tester,
      post(author: other, status: SolidarityStatus.completado),
      onCoordinate: (_) async {},
    );
    expect(find.text('Este favor ya fue completado.'), findsOneWidget);
  });

  testWidgets('sin método de coordinación el botón queda desactivado', (tester) async {
    await open(tester, post(author: other));
    final button = tester.widget<FilledButton>(find.byKey(FavorDetailSheet.coordinateKey));
    expect(button.onPressed, isNull);
  });

  testWidgets('cumple áreas táctiles, etiquetas y contraste', (tester) async {
    final handle = tester.ensureSemantics();
    await open(tester, post(author: other), onCoordinate: (_) async {});
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });
}
