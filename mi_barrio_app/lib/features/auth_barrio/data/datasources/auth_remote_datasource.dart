import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

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

  /// Entrar (o crear la cuenta) con el ID token de Google.
  /// La primera vez el servidor responde 428 si falta el código del barrio.
  Future<Map<String, dynamic>> googleLogin({
    required String idToken,
    String? joinCode,
    String role = 'VECINO',
  }) => _post('/api/v1/auth/google', {
    'id_token': idToken,
    if (joinCode != null && joinCode.trim().isNotEmpty)
      'join_code': joinCode.trim().toUpperCase(),
    'role': role,
  });

  /// Envía (otra vez) el código de 6 dígitos para confirmar el correo.
  Future<String> sendVerificationCode(String email) async => _message(
    await _post('/api/v1/auth/email/send-code', {
      'email': email.trim().toLowerCase(),
    }),
  );

  /// Confirma el correo con el código. Devuelve la sesión actualizada.
  Future<Map<String, dynamic>> verifyEmail({
    required String email,
    required String code,
  }) => _post('/api/v1/auth/email/verify', {
    'email': email.trim().toLowerCase(),
    'code': code.trim(),
  });

  /// "Olvidé mi contraseña": envía un código al correo (si la cuenta existe).
  Future<String> requestPasswordReset(String email) async => _message(
    await _post('/api/v1/auth/password/forgot', {
      'email': email.trim().toLowerCase(),
    }),
  );

  /// Cambia la contraseña con el código y deja la sesión iniciada.
  Future<Map<String, dynamic>> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) => _post('/api/v1/auth/password/reset', {
    'email': email.trim().toLowerCase(),
    'code': code.trim(),
    'new_password': newPassword,
  });

  static String _message(Map<String, dynamic> body) =>
      body['message']?.toString() ?? 'Te enviamos un código al correo.';

  /// Nombre del barrio de un código de invitación (ruta pública, sin sesión).
  /// null = el código no existe. Lanza [AuthException] si no hay conexión.
  Future<String?> lookupNeighborhoodName(String joinCode) async {
    final code = Uri.encodeComponent(joinCode.trim().toUpperCase());
    final response = await _request(
      () => _client
          .get(Uri.parse('$_baseUrl/api/v1/tenants/by-code/$code'))
          .timeout(const Duration(seconds: 8)),
    );
    if (response.statusCode == 404 || response.statusCode == 422) return null;
    final name = _decodeResponse(response)['name'];
    return name is String && name.trim().isNotEmpty ? name.trim() : null;
  }

  Future<Map<String, dynamic>> getCurrentUser(String token) async {
    final response = await _request(
      () => _client
          .get(
            Uri.parse('$_baseUrl/api/v1/auth/me'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(ApiConfig.coldStartTimeout),
    );
    return _decodeResponse(response);
  }

  /// Barrios de la plataforma (solo SUPER_ADMIN).
  Future<List<NeighborhoodSummary>> listNeighborhoods(String token) async {
    final response = await _request(
      () => _client
          .get(
            Uri.parse('$_baseUrl/api/v1/platform/neighborhoods'),
            headers: {'Authorization': 'Bearer $token'},
          )
          .timeout(ApiConfig.coldStartTimeout),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _decodeResponse(response); // lanza AuthException con el detalle
    }
    final body = jsonDecode(response.body);
    if (body is! List) {
      throw const FormatException('Respuesta de barrios inválida');
    }
    return body
        .whereType<Map<String, dynamic>>()
        .map(NeighborhoodSummary.fromJson)
        .toList(growable: false);
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
          .timeout(ApiConfig.coldStartTimeout),
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
          .timeout(ApiConfig.coldStartTimeout),
    );
    return _decodeResponse(response);
  }

  static const _noInternet = AuthException(
    'No pudimos conectar con el servidor. Revisa tus datos móviles o el Wi-Fi '
    'y vuelve a intentar.',
  );

  Future<http.Response> _request(
    Future<http.Response> Function() request,
  ) async {
    try {
      return await request();
    } on AuthException {
      rethrow;
    } on TimeoutException {
      throw const AuthException(
        'El servidor tardó demasiado en responder. Puede estar despertando: '
        'espera unos segundos y vuelve a intentar.',
      );
    } on SocketException {
      throw _noInternet;
    } on http.ClientException {
      // `http` envuelve aquí los errores de conexión (sin red, DNS, etc.).
      throw _noInternet;
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
