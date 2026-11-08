import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'auth_remote_datasource.dart';

/// Pide a Google un "ID token" para mandarlo al servidor.
///
/// Se configura al compilar con el **Web client ID** del proyecto de Google
/// Cloud (el mismo que el servidor tiene en `GOOGLE_CLIENT_IDS`):
///
/// ```
/// flutter build apk --release --dart-define=GOOGLE_SERVER_CLIENT_ID=xxxx.apps.googleusercontent.com
/// ```
abstract class GoogleIdTokenSource {
  /// false en Windows/web de escritorio: ahí no hay "Entrar con Google".
  bool get isAvailable;

  /// El ID token, o null si el vecino cerró la ventana de Google.
  /// Lanza [AuthException] con un mensaje para mostrar si algo falla.
  Future<String?> getIdToken();

  /// Cierra la sesión de Google en el teléfono (para poder elegir otra cuenta).
  Future<void> signOut();
}

class GoogleSignInClient implements GoogleIdTokenSource {
  GoogleSignInClient();

  static const serverClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
  );

  bool _initialized = false;

  @override
  bool get isAvailable => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<void> _init() async {
    if (_initialized) return;
    await GoogleSignIn.instance.initialize(serverClientId: serverClientId);
    _initialized = true;
  }

  @override
  Future<String?> getIdToken() async {
    if (!isAvailable) {
      throw const AuthException(
        'Entrar con Google solo está disponible en el celular.',
      );
    }
    if (serverClientId.isEmpty) {
      throw const AuthException(
        'Entrar con Google todavía no está configurado en esta versión. '
        'Usa tu correo y contraseña.',
      );
    }
    try {
      await _init();
      // Sin sesión previa: así Google siempre deja elegir la cuenta (teléfono compartido).
      await GoogleSignIn.instance.signOut();
      final account = await GoogleSignIn.instance.authenticate();
      final token = account.authentication.idToken;
      if (token == null || token.isEmpty) {
        throw const AuthException(
          'Google no devolvió tu cuenta. Intenta de nuevo.',
        );
      }
      return token;
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) return null;
      throw const AuthException(
        'No se pudo entrar con Google. Revisa tu conexión e intenta de nuevo.',
      );
    }
  }

  @override
  Future<void> signOut() async {
    if (!isAvailable || !_initialized) return;
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Cerrar la sesión de Google es opcional: la de Mi Barrio ya se cerró.
    }
  }
}

/// Reemplazable en las pruebas.
final googleIdTokenSourceProvider = Provider<GoogleIdTokenSource>(
  (ref) => GoogleSignInClient(),
);
