// Comentarios, reseñas y chat de un favor (vienen del servidor).

String _s(Object? v) => v?.toString() ?? '';

DateTime _date(Object? v) =>
    DateTime.tryParse(v?.toString() ?? '')?.toLocal() ?? DateTime.now();

/// Un comentario público de un favor.
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

/// Calificación entre vecinos al terminar un favor (1 a 5 estrellas).
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
    comment: (j['comment'] as String?)?.trim().isEmpty ?? true
        ? null
        : j['comment'] as String,
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
