import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_barrio_app/core/auth/auth_session_store.dart';
import 'package:mi_barrio_app/features/moderation/data/suspended_accounts.dart';
import 'package:mi_barrio_app/features/moderation/presentation/suspended_accounts_card.dart';

class _FakeDs extends SuspendedAccountsDatasource {
  _FakeDs() : super(tenantId: 't1');
  final reactivated = <String>[];
  List<SuspendedAccount> items = [
    SuspendedAccount(userId: 'u1', fullName: 'Rosa Vecina', email: 'rosa@correo.com', reportCount: 3, suspendedAt: DateTime(2026, 11, 8)),
  ];

  @override
  Future<List<SuspendedAccount>> list() async => items;

  @override
  Future<void> reactivate(String userId) async => reactivated.add(userId);
}

void main() {
  testWidgets('el jefe del barrio ve al suspendido y lo reactiva con confirmación', (tester) async {
    final ds = _FakeDs();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: SuspendedAccountsCard(tenantId: 't1', datasource: ds))),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Rosa Vecina'), findsOneWidget);
    expect(find.textContaining('Reportado por 3 vecinos'), findsOneWidget);

    await tester.tap(find.byKey(SuspendedAccountsCard.reactivateKey('u1')));
    await tester.pumpAndSettle();
    expect(find.text('¿Reactivar a Rosa Vecina?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Reactivar').last);
    await tester.pumpAndSettle();

    expect(ds.reactivated, ['u1']);
    expect(find.text('Rosa Vecina'), findsNothing);
    expect(find.textContaining('ya puede volver a usar Mi Barrio'), findsOneWidget);
  });

  testWidgets('sin suspendidos lo dice claramente', (tester) async {
    final ds = _FakeDs()..items = [];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SuspendedAccountsCard(tenantId: 't1', datasource: ds)),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('No hay cuentas suspendidas'), findsOneWidget);
  });

  test('un 401 por suspensión trae el motivo; uno normal no', () {
    expect(
      AuthSessionStore.reasonFrom('{"error":"Tu cuenta está suspendida. Habla con el jefe de tu barrio."}'),
      contains('suspendida'),
    );
    expect(AuthSessionStore.reasonFrom('{"error":"La sesión ya no es válida."}'), isNull);
    expect(AuthSessionStore.reasonFrom('no es json'), isNull);
  });
}
