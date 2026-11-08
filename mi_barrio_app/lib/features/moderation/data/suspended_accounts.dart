import '../../../core/network/api_client.dart';

/// Vecino suspendido por reportes (3 vecinos distintos reportaron sus
/// publicaciones). Solo el jefe del barrio lo puede reactivar.
class SuspendedAccount {
  const SuspendedAccount({
    required this.userId,
    required this.fullName,
    required this.reportCount,
    this.email,
    this.suspendedAt,
  });

  factory SuspendedAccount.fromJson(Map<String, dynamic> json) =>
      SuspendedAccount(
        userId: json['user_id']?.toString() ?? '',
        fullName: json['full_name']?.toString() ?? 'Vecino',
        email: json['email']?.toString(),
        suspendedAt: DateTime.tryParse('${json['suspended_at'] ?? ''}')?.toLocal(),
        reportCount: (json['report_count'] as num?)?.toInt() ?? 0,
      );

  final String userId;
  final String fullName;
  final String? email;
  final DateTime? suspendedAt;
  final int reportCount;
}

/// Panel del jefe del barrio: lista las cuentas suspendidas por reportes y las reactiva.
class SuspendedAccountsDatasource {
  SuspendedAccountsDatasource({required this.tenantId, ApiClient? client})
    : _api = client ?? ApiClient();

  final String tenantId;
  final ApiClient _api;

  Future<List<SuspendedAccount>> list() async {
    final body = ApiClient.decodeOrThrow(
      await _api.get('/api/v1/moderation/suspended', tenantId),
    );
    return [
      for (final item in (body as List? ?? const []))
        if (item is Map<String, dynamic>) SuspendedAccount.fromJson(item),
    ];
  }

  Future<void> reactivate(String userId) async {
    ApiClient.decodeOrThrow(
      await _api.post(
        '/api/v1/moderation/suspended/$userId/reactivate',
        tenantId,
        const <String, Object?>{},
      ),
    );
  }
}
