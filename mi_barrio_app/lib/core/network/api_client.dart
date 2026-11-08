import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../auth/auth_session_store.dart';

/// Dirección del backend FastAPI.
///
/// Se puede fijar al compilar:
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000
/// Por defecto:
/// - Emulador Android → http://10.0.2.2:8000 (la PC vista desde el emulador)
/// - Windows / Linux  → http://localhost:8000
class ApiConfig {
  ApiConfig._();

  static const _fromBuild = String.fromEnvironment('API_BASE_URL');
  static const timeout = Duration(seconds: 30);

  static String get baseUrl {
    if (_fromBuild.isNotEmpty) return _fromBuild;
    if (!kIsWeb && Platform.isAndroid) return 'http://10.0.2.2:8000';
    return 'http://localhost:8000';
  }
}

/// Cliente HTTP que agrega siempre el header `X-Tenant-ID` y un timeout.
class ApiClient {
  ApiClient({String? baseUrl, http.Client? client})
    : baseUrl = baseUrl ?? ApiConfig.baseUrl,
      _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  Map<String, String> _headers(String tenantId) => {
    'Content-Type': 'application/json',
    'X-Tenant-ID': tenantId,
    if (AuthSessionStore.instance.token case final token?)
      'Authorization': 'Bearer $token',
  };

  Uri uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  Future<http.Response> get(
    String path,
    String tenantId, {
    Map<String, String>? query,
  }) => _client
      .get(uri(path, query), headers: _headers(tenantId))
      .timeout(ApiConfig.timeout);

  Future<http.Response> post(String path, String tenantId, Object body) =>
      _client
          .post(uri(path), headers: _headers(tenantId), body: jsonEncode(body))
          .timeout(ApiConfig.timeout);

  Future<http.Response> patch(String path, String tenantId, Object body) =>
      _client
          .patch(uri(path), headers: _headers(tenantId), body: jsonEncode(body))
          .timeout(ApiConfig.timeout);

  /// Cuerpo JSON de [response]; si el estado no es 2xx lanza [Exception]
  /// con el mensaje del servidor (`detail` / `error`).
  static Object? decodeOrThrow(http.Response response) {
    Object? body;
    try {
      body = jsonDecode(response.body);
    } on FormatException {
      body = null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = body is Map ? body['detail'] ?? body['error'] : null;
      throw Exception(message?.toString() ?? 'No se pudo completar la acción');
    }
    return body;
  }
}
