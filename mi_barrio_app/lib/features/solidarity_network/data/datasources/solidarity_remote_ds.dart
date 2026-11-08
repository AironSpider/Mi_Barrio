import 'dart:convert';

import '../../../../core/network/api_client.dart';
import '../models/favor_interactions.dart';

/// Lo que del favor vive en el servidor y necesita internet: la foto,
/// los comentarios y las reseñas (el chat está en `features/chat`).
class SolidarityRemoteDatasource {
  SolidarityRemoteDatasource({ApiClient? api}) : _api = api ?? ApiClient();

  final ApiClient _api;

  static String _base(String postId) => '/api/v1/solidarity/$postId';

  List<Map<String, dynamic>> _list(Object? body) => body is List
      ? body.whereType<Map<String, dynamic>>().toList(growable: false)
      : const [];

  /// Foto del favor en base64, o null si no tiene / no hay red.
  Future<String?> fetchPhoto(String tenantId, String postId) async {
    try {
      final r = await _api.get('${_base(postId)}/photo', tenantId);
      if (r.statusCode != 200) return null;
      final body = jsonDecode(r.body);
      final photo = body is Map ? body['photo_b64'] : null;
      return photo is String && photo.isNotEmpty ? photo : null;
    } catch (_) {
      return null;
    }
  }

  Future<List<PostComment>> comments(String tenantId, String postId) async {
    final body = ApiClient.decodeOrThrow(
      await _api.get('${_base(postId)}/comments', tenantId),
    );
    return _list(body).map(PostComment.fromJson).toList(growable: false);
  }

  Future<PostComment> addComment(
    String tenantId,
    String postId,
    String text,
  ) async {
    final body = ApiClient.decodeOrThrow(
      await _api.post('${_base(postId)}/comments', tenantId, {'body': text}),
    );
    return PostComment.fromJson(body as Map<String, dynamic>);
  }

  Future<void> deleteComment(
    String tenantId,
    String postId,
    String commentId,
  ) async {
    ApiClient.decodeOrThrow(
      await _api.delete('${_base(postId)}/comments/$commentId', tenantId),
    );
  }

  Future<List<FavorReview>> reviews(String tenantId, String postId) async {
    final body = ApiClient.decodeOrThrow(
      await _api.get('${_base(postId)}/reviews', tenantId),
    );
    return _list(body).map(FavorReview.fromJson).toList(growable: false);
  }

  Future<FavorReview> addReview(
    String tenantId,
    String postId, {
    required int rating,
    String? comment,
  }) async {
    final body = ApiClient.decodeOrThrow(
      await _api.post('${_base(postId)}/reviews', tenantId, {
        'rating': rating,
        if (comment != null && comment.trim().isNotEmpty)
          'comment': comment.trim(),
      }),
    );
    return FavorReview.fromJson(body as Map<String, dynamic>);
  }
}
