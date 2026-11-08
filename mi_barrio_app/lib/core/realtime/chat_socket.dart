import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../features/chat/data/chat_models.dart';
import '../auth/auth_session_store.dart';
import '../barrio_context/tenant_session.dart';
import '../network/api_client.dart';

/// Estado de la conexión en tiempo real (para el aviso en el chat).
enum RealtimeStatus { disconnected, connecting, connected }

/// Canal en tiempo real del chat (favores y servicios, WebSocket `/api/v1/ws/chat`).
///
/// - Se conecta cuando hay al menos un chat abierto ([acquire]) y se cierra
///   cuando ya no ([release]).
/// - Si se corta (sin señal, servidor reiniciándose) reintenta solo, cada vez
///   con más espera (1, 2, 4… hasta 30 s).
/// - Mantiene viva la conexión con un "ping" cada 25 s.
/// - Los mensajes se ENVÍAN por REST (quedan guardados aunque el otro no
///   esté conectado); por aquí solo se RECIBEN al instante.
class ChatSocket {
  ChatSocket._();
  static final ChatSocket instance = ChatSocket._();

  /// Para los tests: reemplaza la conexión real.
  @visibleForTesting
  static WebSocketChannel Function(Uri uri) connector =
      WebSocketChannel.connect;

  final _messages = StreamController<ChatMessage>.broadcast();
  final ValueNotifier<RealtimeStatus> status = ValueNotifier(
    RealtimeStatus.disconnected,
  );

  /// Mensajes nuevos de cualquier chat del vecino.
  Stream<ChatMessage> get messages => _messages.stream;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _ping;
  Timer? _retry;
  int _users = 0;
  int _attempt = 0;

  /// Solo para tests: simula un mensaje recibido por el WebSocket.
  @visibleForTesting
  void injectForTesting(ChatMessage message) => _messages.add(message);

  void acquire() {
    _users++;
    if (_users == 1) _connect();
  }

  void release() {
    if (_users == 0) return;
    _users--;
    if (_users == 0) _close();
  }

  Uri _uri() {
    final base = Uri.parse(ApiConfig.baseUrl);
    return base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '/api/v1/ws/chat',
      queryParameters: {
        'token': AuthSessionStore.instance.token ?? '',
        'tenant': TenantSession.instance.tenantId,
      },
    );
  }

  Future<void> _connect() async {
    if (_users == 0) return;
    status.value = RealtimeStatus.connecting;
    try {
      final channel = connector(_uri());
      await channel.ready;
      if (_users == 0) {
        await channel.sink.close();
        return;
      }
      _channel = channel;
      _attempt = 0;
      status.value = RealtimeStatus.connected;
      _sub = channel.stream.listen(
        _onData,
        onDone: _onLost,
        onError: (_) => _onLost(),
      );
      _ping = Timer.periodic(
        const Duration(seconds: 25),
        (_) => _channel?.sink.add('ping'),
      );
    } catch (_) {
      _onLost();
    }
  }

  void _onData(dynamic data) {
    if (data is! String || data == 'pong') return;
    try {
      final json = jsonDecode(data);
      if (json is Map<String, dynamic> &&
          json['type'] == 'chat_message' &&
          json['message'] is Map<String, dynamic>) {
        _messages.add(
          ChatMessage.fromJson(json['message'] as Map<String, dynamic>),
        );
      }
    } catch (_) {
      /* mensaje desconocido: se ignora */
    }
  }

  void _onLost() {
    _cleanup();
    if (_users == 0) {
      status.value = RealtimeStatus.disconnected;
      return;
    }
    status.value = RealtimeStatus.connecting;
    final seconds = [1, 2, 4, 8, 15, 30][_attempt.clamp(0, 5)];
    _attempt++;
    _retry = Timer(Duration(seconds: seconds), _connect);
  }

  void _cleanup() {
    _ping?.cancel();
    _ping = null;
    unawaited(_sub?.cancel());
    _sub = null;
    unawaited(_channel?.sink.close());
    _channel = null;
  }

  void _close() {
    _retry?.cancel();
    _retry = null;
    _cleanup();
    _attempt = 0;
    status.value = RealtimeStatus.disconnected;
  }
}
