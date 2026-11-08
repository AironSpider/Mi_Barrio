import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class AuthSessionStore {
  AuthSessionStore._();

  static final instance = AuthSessionStore._();
  static const _sessionKey = 'auth_session_v1';
  /// Emite el motivo para mostrarle al vecino (p. ej. "Tu cuenta está
  /// suspendida…"), o null si solo venció la sesión.
  final StreamController<String?> _sessionExpired =
      StreamController<String?>.broadcast();

  String? _token;

  String? get token => _token;
  Stream<String?> get onSessionExpired => _sessionExpired.stream;

  Future<void> save(Map<String, dynamic> session) async {
    final token = session['token'];
    if (token is! String || token.isEmpty) {
      throw const FormatException('No se puede guardar una sesión sin token');
    }
    _token = token;
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(_sessionKey, jsonEncode(session));
    if (!saved) {
      _token = null;
      await preferences.remove(_sessionKey);
      throw StateError('No se pudo persistir la sesión en el dispositivo');
    }
  }

  Future<Map<String, dynamic>?> read() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_sessionKey);
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      await clear();
      throw const FormatException('La sesión local tiene un formato inválido');
    }
    final token = decoded['token'];
    if (token is! String || token.isEmpty) {
      await clear();
      throw const FormatException('La sesión local no contiene un token');
    }
    _token = token;
    return decoded;
  }

  Future<void> clear() async {
    _token = null;
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_sessionKey);
  }

  Future<void> invalidate([String? reason]) async {
    await clear();
    _sessionExpired.add(reason);
  }

  /// Motivo de un 401 que vale la pena mostrar (cuenta suspendida). null si
  /// solo venció la sesión. [body] es el cuerpo JSON de la respuesta.
  static String? reasonFrom(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final text = (decoded['error'] ?? decoded['detail'])?.toString();
        if (text != null && text.toLowerCase().contains('suspendida')) {
          return text;
        }
      }
    } on FormatException {
      return null;
    }
    return null;
  }
}
