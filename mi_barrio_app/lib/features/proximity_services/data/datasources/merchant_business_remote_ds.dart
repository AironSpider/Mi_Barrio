import '../../../../core/network/api_client.dart';

class MerchantBusinessRemoteDatasource {
  MerchantBusinessRemoteDatasource({ApiClient? api})
    : _api = api ?? ApiClient();

  final ApiClient _api;

  Future<List<Map<String, dynamic>>> recommendations({
    required String tenantId,
    required String serviceId,
  }) async {
    final response = await _api.get(
      '/api/v1/services/$serviceId/endorsements',
      tenantId,
    );
    final body = ApiClient.decodeOrThrow(response);
    if (body is! List) {
      throw const FormatException('Respuesta de recomendaciones inválida');
    }
    return body.whereType<Map<String, dynamic>>().toList(growable: false);
  }

  Future<void> reply({
    required String tenantId,
    required String serviceId,
    required String recommendationId,
    required String text,
  }) async {
    final response = await _api.post(
      '/api/v1/services/$serviceId/recommendations/$recommendationId/reply',
      tenantId,
      {'reply': text},
    );
    ApiClient.decodeOrThrow(response);
  }
}
