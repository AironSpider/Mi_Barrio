/// Validaciones de los formularios de cuenta, en lenguaje simple.
class AuthValidators {
  AuthValidators._();

  static final _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');
  static final _hasLetter = RegExp(r'[A-Za-zÁÉÍÓÚÜÑáéíóúüñ]');
  static final _hasNumber = RegExp(r'\d');
  static final _hasSymbol = RegExp(r'[^A-Za-z0-9ÁÉÍÓÚÜÑáéíóúüñ\s]');
  static final _onlyDigits = RegExp(r'^\d{6}$');

  /// Contraseñas tan comunes que no se aceptan aunque cumplan el largo.
  static const _common = {
    '12345678',
    '123456789',
    '1234567890',
    'password',
    'contraseña',
    'contrasena',
    'qwerty123',
    '11111111',
    '00000000',
    'abc12345',
    'password1',
    'iloveyou',
    'mibarrio1',
    '87654321',
  };

  static String? email(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Escribe tu correo';
    if (email.contains(' ')) return 'El correo no lleva espacios';
    return _email.hasMatch(email)
        ? null
        : 'Revisa tu correo (ejemplo: nombre@correo.com)';
  }

  static String? fullName(String? value) {
    final name = value?.trim() ?? '';
    if (name.length < 2) return 'Escribe tu nombre';
    if (_hasNumber.hasMatch(name)) return 'El nombre no lleva números';
    return name.length > 150 ? 'Usa un nombre más corto' : null;
  }

  /// Contraseña NUEVA (registro o cambio): 8+ caracteres, con letras y números.
  static String? newPassword(String? value) {
    final password = value ?? '';
    if (password.isEmpty) return 'Crea una contraseña';
    if (password.length < 8) return 'Usa al menos 8 caracteres';
    if (password.length > 128) return 'Usa como máximo 128 caracteres';
    if (_common.contains(password.toLowerCase())) {
      return 'Esa contraseña es muy fácil de adivinar';
    }
    if (!_hasLetter.hasMatch(password) || !_hasNumber.hasMatch(password)) {
      return 'Combina letras y números';
    }
    return null;
  }

  static String? Function(String?) confirmPassword(
    String Function() original,
  ) => (value) {
    if ((value ?? '').isEmpty) return 'Repite tu contraseña';
    return value == original() ? null : 'Las contraseñas no coinciden';
  };

  static String? code(String? value) {
    final code = value?.trim() ?? '';
    if (code.isEmpty) return 'Escribe el código del correo';
    return _onlyDigits.hasMatch(code) ? null : 'El código tiene 6 números';
  }

  static String? joinCode(String? value) => (value?.trim().length ?? 0) >= 3
      ? null
      : 'Escribe el código de tu barrio';

  /// 0 = vacía, 1 = débil, 2 = regular, 3 = buena, 4 = fuerte.
  static int strength(String password) {
    if (password.isEmpty) return 0;
    if (password.length < 8 || _common.contains(password.toLowerCase())) {
      return 1;
    }
    var score = 1;
    if (_hasLetter.hasMatch(password) && _hasNumber.hasMatch(password)) score++;
    if (password.length >= 12) score++;
    if (_hasSymbol.hasMatch(password) ||
        (RegExp('[A-ZÁÉÍÓÚÑ]').hasMatch(password) &&
            RegExp('[a-záéíóúñ]').hasMatch(password))) {
      score++;
    }
    return score.clamp(1, 4);
  }

  static String strengthLabel(int score) => switch (score) {
    0 => '',
    1 => 'Débil',
    2 => 'Regular',
    3 => 'Buena',
    _ => 'Fuerte',
  };
}
