import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_barrio_app/core/barrio_context/tenant_session.dart';
import 'package:mi_barrio_app/core/network/api_client.dart';
import 'package:mi_barrio_app/core/realtime/chat_socket.dart';
import 'package:mi_barrio_app/core/ui_kit/app_theme.dart';
import 'package:mi_barrio_app/features/chat/data/chat_models.dart';
import 'package:mi_barrio_app/features/chat/data/chat_remote_ds.dart';
import 'package:mi_barrio_app/features/chat/presentation/chat_screen.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const _owner = '7d1c2b3a-0000-4abc-8def-0123456789ab';
const _target = ChatTarget(
  kind: ChatKind.service,
  contextId: 'svc-1',
  title: 'Gasfitería Don Pedro',
  ownerUserId: _owner,
);

ChatMessage _msg(String id, String body, DateTime at) => ChatMessage(
      id: id,
      kind: ChatKind.service,
      contextId: 'svc-1',
      neighborUserId: TenantSession.instance.userId,
      senderUserId: _owner,
      senderName: 'Pedro R.',
      body: body,
      createdAt: at,
    );

/// La carga del historial tarda hasta que el test la suelta.
class _SlowChat extends ChatRemoteDatasource {
  _SlowChat() : super(api: ApiClient(baseUrl: 'http://fake'));

  final response = Completer<List<ChatMessage>>();

  @override
  Future<List<ChatMessage>> messages(String tenantId, ChatTarget target, String neighborId) =>
      response.future;
}

void main() {
  setUpAll(() {
    ChatSocket.connector = (_) => throw WebSocketChannelException('sin red');
  });

  testWidgets('un mensaje que llega por WebSocket mientras carga el historial no se pierde',
      (tester) async {
    final remote = _SlowChat();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.day(),
      home: ChatScreen(
        target: _target,
        neighborUserId: TenantSession.instance.userId,
        otherName: 'Pedro R.',
        remote: remote,
      ),
    ));
    await tester.pump();

    final t0 = DateTime.utc(2026, 11, 8, 10);
    ChatSocket.instance.injectForTesting(_msg('m2', 'Sí, voy a las 5', t0.add(const Duration(minutes: 2))));
    await tester.pump();
    // El historial que devuelve el servidor todavía no incluye el mensaje nuevo.
    remote.response.complete([_msg('m1', '¿Atiende hoy?', t0)]);
    await tester.pumpAndSettle();

    expect(find.text('¿Atiende hoy?'), findsOneWidget);
    expect(find.text('Sí, voy a las 5'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('¿Atiende hoy?')).dy,
      lessThan(tester.getTopLeft(find.text('Sí, voy a las 5')).dy),
      reason: 'en orden de llegada',
    );

    await tester.pumpWidget(const SizedBox());
  });
}
