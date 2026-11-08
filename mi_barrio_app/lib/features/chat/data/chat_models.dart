// Chat entre vecinos sobre un favor o un servicio (viene del servidor).

String _s(Object? v) => v?.toString() ?? '';

DateTime _date(Object? v) =>
    DateTime.tryParse(v?.toString() ?? '')?.toLocal() ?? DateTime.now();

/// De qué se habla: un favor del muro o un servicio de un comerciante.
enum ChatKind {
  favor('favor'),
  service('service');

  const ChatKind(this.api);
  final String api;

  static ChatKind fromApi(Object? v) =>
      v == 'service' ? ChatKind.service : ChatKind.favor;
}

/// La publicación del chat y su dueño (autor del favor o comerciante).
class ChatTarget {
  const ChatTarget({
    required this.kind,
    required this.contextId,
    required this.title,
    required this.ownerUserId,
  });

  final ChatKind kind;
  final String contextId;
  final String title;
  final String ownerUserId;
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.kind,
    required this.contextId,
    required this.neighborUserId,
    required this.senderUserId,
    required this.senderName,
    required this.body,
    required this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
    id: _s(j['id']),
    kind: ChatKind.fromApi(j['kind']),
    contextId: _s(j['context_id']),
    neighborUserId: _s(j['neighbor_user_id']),
    senderUserId: _s(j['sender_user_id']),
    senderName: _s(j['sender_name']),
    body: _s(j['body']),
    createdAt: _date(j['created_at']),
  );

  final String id;
  final ChatKind kind;
  final String contextId;
  final String neighborUserId;
  final String senderUserId;
  final String senderName;
  final String body;
  final DateTime createdAt;
}

/// Una conversación, vista por quien consulta ([otherName] = la otra persona).
class ConversationSummary {
  const ConversationSummary({
    required this.kind,
    required this.contextId,
    required this.contextTitle,
    required this.ownerUserId,
    required this.neighborUserId,
    required this.otherUserId,
    required this.otherName,
    required this.lastMessage,
    required this.lastSenderUserId,
    required this.lastAt,
    required this.messageCount,
  });

  factory ConversationSummary.fromJson(Map<String, dynamic> j) =>
      ConversationSummary(
        kind: ChatKind.fromApi(j['kind']),
        contextId: _s(j['context_id']),
        contextTitle: _s(j['context_title']),
        ownerUserId: _s(j['owner_user_id']),
        neighborUserId: _s(j['neighbor_user_id']),
        otherUserId: _s(j['other_user_id']),
        otherName: _s(j['other_name']).isEmpty ? 'Vecino' : _s(j['other_name']),
        lastMessage: _s(j['last_message']),
        lastSenderUserId: _s(j['last_sender_user_id']),
        lastAt: _date(j['last_at']),
        messageCount: (j['message_count'] as num?)?.toInt() ?? 0,
      );

  final ChatKind kind;
  final String contextId;
  final String contextTitle;
  final String ownerUserId;
  final String neighborUserId;
  final String otherUserId;
  final String otherName;
  final String lastMessage;
  final String lastSenderUserId;
  final DateTime lastAt;
  final int messageCount;

  ChatTarget get target => ChatTarget(
    kind: kind,
    contextId: contextId,
    title: contextTitle,
    ownerUserId: ownerUserId,
  );
}
