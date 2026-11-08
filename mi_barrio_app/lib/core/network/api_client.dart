import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../auth/auth_session_store.dart';

/// Dirección del backend FastAPI.
///
/// Por defecto, el servidor de PRODUCCIÓN en Render (funciona desde cualquier
/// red: datos móviles, otro Wi-Fi, APK de demo).
///
/// Para desarrollar con el backend local, fijarlo al compilar:
///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000      (emulador Android)
///   flutter run --dart-define=API_BASE_URL=http://localhost:8000     (Linux / Windows)
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.20:8000  (celular, IP de la PC)
class ApiConfig {
  ApiConfig._();

  static const productionUrl = 'https://mi-barrio-backend-lad7.onrender.com';
  static const _fromBuild = String.fromEnvironment('API_BASE_URL');

  /// Render gratis tarda ~50 s en despertar: con 30 s el primer login fallaba.
  static const timeout = Duration(seconds: 60);

  /// El plan gratis de Render apaga el servidor tras 15 min sin uso y tarda
  /// ~1 minuto en volver: login, registro y sesión esperan más.
  static const coldStartTimeout = Duration(seconds: 90);

  static String get baseUrl => _fromBuild.isNotEmpty ? _fromBuild : productionUrl;
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

  /// true si el backend responde a /health/live (útil porque "tener Wi-Fi"
  /// no garantiza que el servidor sea alcanzable). /health/live no toca la
  /// base de datos, así que no espera a que Neon despierte.
  Future<bool> isServerReachable({
    Duration timeout = const Duration(seconds: 8),
  }) async {
    try {
      final r = await _client.get(uri('/health/live')).timeout(timeout);
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Despierta al servidor sin esperar la respuesta (al abrir la app y al
  /// volver a ella), para que esté listo cuando el vecino toque "Ingresar".
  static void wakeUp() {
    unawaited(
      ApiClient().isServerReachable(timeout: const Duration(seconds: 60)),
    );
  }
}
