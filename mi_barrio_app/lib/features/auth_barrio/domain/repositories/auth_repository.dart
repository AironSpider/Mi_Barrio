import '../entities/user_entity.dart';

abstract interface class AuthRepository {
  Future<UserEntity> login({required String email, required String password});

  Future<UserEntity> register({
    required String fullName,
    required String email,
    required String password,
    required UserRole role,
    required String joinCode,
    required bool acceptedTerms,
  });

  /// Entra o crea la cuenta con Google. Lanza `AuthException` con
  /// statusCode 428 si es una cuenta nueva y falta el código del barrio.
  Future<UserEntity> signInWithGoogle({
    required String idToken,
    String? joinCode,
    UserRole role = UserRole.vecino,
    bool acceptedTerms = false,
  });

  /// Envía otra vez el código de verificación. Devuelve el mensaje para mostrar.
  Future<String> sendVerificationCode(String email);

  /// Confirma el correo con el código y devuelve la sesión actualizada.
  Future<UserEntity> verifyEmail({required String email, required String code});

  /// Quien entró con Google crea su contraseña (pide sesión iniciada).
  Future<UserEntity> setPassword(String password);

  /// "Olvidé mi contraseña": envía un código al correo.
  Future<String> requestPasswordReset(String email);

  /// Cambia la contraseña con el código y deja la sesión iniciada.
  Future<UserEntity> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  });

  Future<UserEntity?> restoreSession();

  Future<NeighborhoodProvisionEntity> createNeighborhood({
    required String neighborhoodName,
    String? existingJoinCode,
    required String adminFullName,
    required String adminEmail,
    required String adminPassword,
    required double centerLat,
    required double centerLng,
  });

  Future<void> logout();

  /// Borra la cuenta en el servidor (necesita internet).
  Future<void> deleteAccount({required String tenantId});

  Future<void> purgeLocalUserData({
    required String tenantId,
    required String userId,
  });

  /// Sesión vencida (401): se conservan los cambios hechos sin internet.
  Future<void> keepPendingDataFor({
    required String tenantId,
    required String userId,
  });

  /// Tras iniciar sesión: si los pendientes son de otra persona se borran;
  /// si son de la misma, se conservan para subirlos.
  Future<void> reconcilePendingData(UserEntity user);
}
