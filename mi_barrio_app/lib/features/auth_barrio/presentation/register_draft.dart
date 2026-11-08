import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Lo que el vecino escribió al crear su cuenta, para "Volver para cambiar
/// datos" (aunque cierre la app). **Nunca guarda la contraseña**: por
/// seguridad se vuelve a escribir.
class RegisterDraft {
  const RegisterDraft({
    required this.joinCode,
    required this.fullName,
    required this.email,
    required this.role,
  });

  final String joinCode;
  final String fullName;
  final String email;

  /// `VECINO` o `COMERCIANTE`.
  final String role;

  static const _key = 'register_draft';

  /// true = al volver al inicio de sesión se abre "Crear cuenta" con el
  /// borrador (lo pide "Volver para cambiar datos").
  static bool reopenRequested = false;

  Map<String, String> _toJson() => {
    'join_code': joinCode,
    'full_name': fullName,
    'email': email,
    'role': role,
  };

  static Future<void> save(RegisterDraft draft) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(draft._toJson()));
    } catch (_) {
      // Sin borrador: el registro sigue igual.
    }
  }

  static Future<RegisterDraft?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return null;
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      return RegisterDraft(
        joinCode: '${json['join_code'] ?? ''}',
        fullName: '${json['full_name'] ?? ''}',
        email: '${json['email'] ?? ''}',
        role: '${json['role'] ?? 'VECINO'}',
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    reopenRequested = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {
      // Nada que borrar.
    }
  }
}
