import '../../../../core/network/api_client.dart';

class AdminMerchantApprovalRemoteDatasource {
  AdminMerchantApprovalRemoteDatasource({ApiClient? api})
    : _api = api ?? ApiClient();

  final ApiClient _api;

  Future<List<Map<String, dynamic>>> pendingMerchants(String tenantId) async {
    final response = await _api.get(
      '/api/v1/users/pending-merchants',
      tenantId,
    );
    final body = ApiClient.decodeOrThrow(response);
    if (body is! List) {
      throw const FormatException(
        'Respuesta de comerciantes pendientes inválida',
      );
    }
    return body.whereType<Map<String, dynamic>>().toList(growable: false);
  }

  Future<void> approve(String tenantId, String userId) async {
    ApiClient.decodeOrThrow(
      await _api.patch(
        '/api/v1/users/$userId/approve-merchant',
        tenantId,
        const <String, Object?>{},
      ),
    );
  }

  Future<void> reject(String tenantId, String userId) async {
    ApiClient.decodeOrThrow(
      await _api.patch(
        '/api/v1/users/$userId/reject-merchant',
        tenantId,
        const <String, Object?>{},
      ),
    );
  }
}
