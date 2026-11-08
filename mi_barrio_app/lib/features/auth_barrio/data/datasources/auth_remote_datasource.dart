import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../../core/network/api_client.dart';
import '../../domain/entities/user_entity.dart';

class AuthException implements Exception {
  const AuthException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class AuthRemoteDatasource {
  AuthRemoteDatasource({String? baseUrl, http.Client? client})
    : _baseUrl = baseUrl ?? ApiConfig.baseUrl,
      _client = client ?? http.Client();

  final String _baseUrl;
  final http.Client _client;

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) => _post('/api/v1/auth/login', {
    'email': email.trim().toLowerCase(),
    'password': password,
  });

  Future<Map<String, dynamic>> register({
    required String fullName,
    required String email,
    required String password,
    required String role,
    required String joinCode,
  }) => _post('/api/v1/auth/register', {
    'full_name': fullName.trim(),
    'email': email.trim().toLowerCase(),
    'password': password,
    'role': role,
    'join_code': joinCode.trim().toUpperCase(),
  });

  Future<Map<String, dynamic>> getCurrentUser(String token) async {
    final response = await _request(
      () => _client
          .get(
            Uri.parse('$_baseUrl/api/v1/auth/me'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(ApiConfig.timeout),
    );
    return _decodeResponse(response);
  }

  Future<NeighborhoodProvisionEntity> createNeighborhood({
    required String token,
    required String neighborhoodName,
    String? existingJoinCode,
    required String adminFullName,
    required String adminEmail,
    required String adminPassword,
    required double centerLat,
    required double centerLng,
  }) async {
    final response = await _request(
      () => _client
          .post(
            Uri.parse('$_baseUrl/api/v1/platform/neighborhoods'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              if (neighborhoodName.trim().isNotEmpty)
                'neighborhood_name': neighborhoodName.trim(),
              if (existingJoinCode != null &&
                  existingJoinCode.trim().isNotEmpty)
                'join_code': existingJoinCode.trim().toUpperCase(),
              'admin_full_name': adminFullName.trim(),
              'admin_email': adminEmail.trim().toLowerCase(),
              'admin_password': adminPassword,
              'center_lat': centerLat,
              'center_lng': centerLng,
            }),
          )
          .timeout(ApiConfig.timeout),
    );
    final data = _decodeResponse(response);
    final neighborhood = data['neighborhood'];
    final administrator = data['administrator'];
    if (neighborhood is! Map<String, dynamic> ||
        administrator is! Map<String, dynamic>) {
      throw const FormatException('Respuesta de creación de barrio incompleta');
    }
    return NeighborhoodProvisionEntity(
      neighborhoodName: neighborhood['name']?.toString() ?? '',
      joinCode: neighborhood['join_code']?.toString() ?? '',
      adminFullName: administrator['full_name']?.toString() ?? '',
      adminEmail: administrator['email']?.toString() ?? '',
    );
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, String> body,
  ) async {
    final response = await _request(
      () => _client
          .post(
            Uri.parse('$_baseUrl$path'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(ApiConfig.timeout),
    );
    return _decodeResponse(response);
  }

  Future<http.Response> _request(
    Future<http.Response> Function() request,
  ) async {
    try {
      return await request();
    } on AuthException {
      rethrow;
    } on TimeoutException {
      throw const AuthException(
        'No pudimos contactar al servidor. Verifica que esté encendido, '
        'que tu celular y la computadora estén en la misma red Wi-Fi y '
        'que la app use la IP de la computadora.',
      );
    } catch (error) {
      throw AuthException('No se pudo conectar con el servidor: $error');
    }
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    Map<String, dynamic> decoded;
    try {
      final body = jsonDecode(response.body);
      decoded = body is Map<String, dynamic> ? body : <String, dynamic>{};
    } on FormatException {
      decoded = <String, dynamic>{};
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = decoded['detail'] ?? decoded['error'] ?? decoded['message'];
      throw AuthException(
        error?.toString() ?? 'El servidor respondió ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }
    return decoded;
  }
}
