// Comentarios, reseñas y chat de un favor (vienen del servidor).

String _s(Object? v) => v?.toString() ?? '';

DateTime _date(Object? v) =>
    DateTime.tryParse(v?.toString() ?? '')?.toLocal() ?? DateTime.now();

class PostComment {
  const PostComment({
    required this.id,
    required this.authorUserId,
    required this.authorName,
    required this.body,
    required this.createdAt,
  });

  factory PostComment.fromJson(Map<String, dynamic> j) => PostComment(
        id: _s(j['id']),
        authorUserId: _s(j['author_user_id']),
        authorName: _s(j['author_name']).isEmpty ? 'Vecino' : _s(j['author_name']),
        body: _s(j['body']),
        createdAt: _date(j['created_at']),
      );

  final String id;
  final String authorUserId;
  final String authorName;
  final String body;
  final DateTime createdAt;
}

class FavorReview {
  const FavorReview({
    required this.id,
    required this.reviewerUserId,
    required this.reviewerName,
    required this.reviewedUserId,
    required this.reviewedName,
    required this.rating,
    this.comment,
    required this.createdAt,
  });

  factory FavorReview.fromJson(Map<String, dynamic> j) => FavorReview(
        id: _s(j['id']),
        reviewerUserId: _s(j['reviewer_user_id']),
        reviewerName: _s(j['reviewer_name']),
        reviewedUserId: _s(j['reviewed_user_id']),
        reviewedName: _s(j['reviewed_name']),
        rating: (j['rating'] as num?)?.toInt() ?? 0,
        comment: (j['comment'] as String?)?.trim().isEmpty ?? true ? null : j['comment'] as String,
        createdAt: _date(j['created_at']),
      );

  final String id;
  final String reviewerUserId;
  final String reviewerName;
  final String reviewedUserId;
  final String reviewedName;
  final int rating;
  final String? comment;
  final DateTime createdAt;
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.postId,
    required this.neighborUserId,
    required this.senderUserId,
    required this.senderName,
    required this.body,
    required this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        id: _s(j['id']),
        postId: _s(j['post_id']),
        neighborUserId: _s(j['neighbor_user_id']),
        senderUserId: _s(j['sender_user_id']),
        senderName: _s(j['sender_name']),
        body: _s(j['body']),
        createdAt: _date(j['created_at']),
      );

  final String id;
  final String postId;
  final String neighborUserId;
  final String senderUserId;
  final String senderName;
  final String body;
  final DateTime createdAt;
}

class ConversationSummary {
  const ConversationSummary({
    required this.neighborUserId,
    required this.neighborName,
    required this.lastMessage,
    required this.lastSenderUserId,
    required this.lastAt,
    required this.messageCount,
  });

  factory ConversationSummary.fromJson(Map<String, dynamic> j) => ConversationSummary(
        neighborUserId: _s(j['neighbor_user_id']),
        neighborName: _s(j['neighbor_name']),
        lastMessage: _s(j['last_message']),
        lastSenderUserId: _s(j['last_sender_user_id']),
        lastAt: _date(j['last_at']),
        messageCount: (j['message_count'] as num?)?.toInt() ?? 0,
      );

  final String neighborUserId;
  final String neighborName;
  final String lastMessage;
  final String lastSenderUserId;
  final DateTime lastAt;
  final int messageCount;
}
