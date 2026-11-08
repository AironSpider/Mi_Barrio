import '../../../core/network/api_client.dart';
import 'chat_models.dart';

/// Chat en el servidor (`/api/v1/chat/...`). Necesita internet.
class ChatRemoteDatasource {
  ChatRemoteDatasource({ApiClient? api}) : _api = api ?? ApiClient();

  final ApiClient _api;

  static String _base(ChatTarget t) =>
      '/api/v1/chat/${t.kind.api}/${t.contextId}';

  List<Map<String, dynamic>> _list(Object? body) => body is List
      ? body.whereType<Map<String, dynamic>>().toList(growable: false)
      : const [];

  /// "Mis mensajes": todas mis conversaciones, la más reciente primero.
  Future<List<ConversationSummary>> inbox(String tenantId) async {
    final body = ApiClient.decodeOrThrow(
      await _api.get('/api/v1/chat/inbox', tenantId),
    );
    return _list(body)
        .map(ConversationSummary.fromJson)
        .toList(growable: false);
  }

  /// Conversaciones de una publicación (el dueño ve todas; otro vecino, la suya).
  Future<List<ConversationSummary>> conversations(
    String tenantId,
    ChatTarget target,
  ) async {
    final body = ApiClient.decodeOrThrow(
      await _api.get('${_base(target)}/conversations', tenantId),
    );
    return _list(body)
        .map(ConversationSummary.fromJson)
        .toList(growable: false);
  }

  Future<List<ChatMessage>> messages(
    String tenantId,
    ChatTarget target,
    String neighborId,
  ) async {
    final body = ApiClient.decodeOrThrow(
      await _api.get(
        '${_base(target)}/conversations/$neighborId/messages',
        tenantId,
      ),
    );
    return _list(body).map(ChatMessage.fromJson).toList(growable: false);
  }

  Future<ChatMessage> sendMessage(
    String tenantId,
    ChatTarget target,
    String neighborId,
    String text,
  ) async {
    final body = ApiClient.decodeOrThrow(
      await _api.post(
        '${_base(target)}/conversations/$neighborId/messages',
        tenantId,
        {'body': text},
      ),
    );
    return ChatMessage.fromJson(body as Map<String, dynamic>);
  }
}
