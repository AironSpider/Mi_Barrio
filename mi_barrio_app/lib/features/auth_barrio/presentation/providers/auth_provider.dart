import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/auth_session_store.dart';
import '../../../../core/sync_manager/sync_coordinator.dart';
import '../../data/datasources/auth_remote_datasource.dart';
import '../../data/repositories/auth_repository_impl.dart';
import '../../domain/entities/user_entity.dart';
import '../../domain/repositories/auth_repository.dart';

enum AuthStatus {
  loading,
  authenticatedNeighbor,
  authenticatedMerchant,
  authenticatedNeighborhoodAdmin,
  authenticatedSuperAdmin,
  unauthenticated,
  error,
}

class AuthState {
  const AuthState({required this.status, this.user, this.message});

  const AuthState.loading() : this(status: AuthStatus.loading);
  const AuthState.unauthenticated() : this(status: AuthStatus.unauthenticated);

  final AuthStatus status;
  final UserEntity? user;
  final String? message;

  factory AuthState.authenticated(UserEntity user) => AuthState(
    status: switch (user.role) {
      UserRole.vecino => AuthStatus.authenticatedNeighbor,
      UserRole.comerciante => AuthStatus.authenticatedMerchant,
      UserRole.adminBarrio => AuthStatus.authenticatedNeighborhoodAdmin,
      UserRole.superAdmin => AuthStatus.authenticatedSuperAdmin,
    },
    user: user,
  );
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepositoryImpl(),
);

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(ref.watch(authRepositoryProvider))..restoreSession(),
);

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier(this._repository, {AuthState? initialState})
    : super(initialState ?? const AuthState.loading()) {
    _sessionExpiredSubscription = AuthSessionStore.instance.onSessionExpired
        .listen((_) => unawaited(expireSession()));
  }

  final AuthRepository _repository;
  late final StreamSubscription<void> _sessionExpiredSubscription;

  /// [keepPendingData] = true cuando la sesión VENCE (401): los cambios hechos
  /// sin internet se conservan para subirlos al volver a entrar.
  /// En un cierre de sesión manual se borran los datos locales de la cuenta.
  Future<void> _endCurrentSession(
    UserEntity? user, {
    bool keepPendingData = false,
  }) async {
    await SyncCoordinator.instance.stop();
    try {
      final tenantId = user?.tenantId;
      if (user != null && tenantId != null) {
        if (keepPendingData) {
          await _repository.keepPendingDataFor(
            tenantId: tenantId,
            userId: user.id,
          );
        } else {
          await _repository.purgeLocalUserData(
            tenantId: tenantId,
            userId: user.id,
          );
        }
      }
    } finally {
      await _repository.logout();
    }
  }

  Future<UserEntity> _afterSignIn(UserEntity user) async {
    await _repository.reconcilePendingData(user);
    return user;
  }

  String _message(Object error) {
    final text = error.toString();
    return text.startsWith('Exception: ') ? text.substring(11) : text;
  }

  Future<void> restoreSession() async {
    try {
      final user = await _repository.restoreSession();
      state = user == null
          ? const AuthState.unauthenticated()
          : AuthState.authenticated(user);
    } catch (error) {
      state = AuthState(
        status: AuthStatus.error,
        message: 'No se pudo restaurar la sesión: ${_message(error)}',
      );
    }
  }

  Future<void> login({required String email, required String password}) async {
    final previousUser = state.user;
    state = const AuthState.loading();
    try {
      await _endCurrentSession(previousUser);
      state = AuthState.authenticated(
        await _afterSignIn(
          await _repository.login(email: email, password: password),
        ),
      );
    } catch (error) {
      state = AuthState(status: AuthStatus.error, message: _message(error));
    }
  }

  Future<void> register({
    required String fullName,
    required String email,
    required String password,
    required UserRole role,
    required String joinCode,
  }) async {
    final previousUser = state.user;
    state = const AuthState.loading();
    try {
      await _endCurrentSession(previousUser);
      state = AuthState.authenticated(
        await _afterSignIn(
          await _repository.register(
            fullName: fullName,
            email: email,
            password: password,
            role: role,
            joinCode: joinCode,
          ),
        ),
      );
    } catch (error) {
      state = AuthState(status: AuthStatus.error, message: _message(error));
    }
  }

  // ─────────────── Cuentas reales: Google, verificar correo, contraseña ───────────────
  // Estas acciones NO ponen el estado global en "cargando": la pantalla muestra
  // su propio indicador. Así, si Google pide el código del barrio o un código
  // está mal, el vecino sigue en la misma pantalla con lo que escribió.

  /// Entra o crea la cuenta con Google. Devuelve [GoogleSignInOutcome].
  Future<GoogleSignInResult> signInWithGoogle({
    required String idToken,
    String? joinCode,
    UserRole role = UserRole.vecino,
  }) async {
    final previousUser = state.user;
    try {
      final user = await _repository.signInWithGoogle(
        idToken: idToken,
        joinCode: joinCode,
        role: role,
      );
      if (previousUser != null && previousUser.id != user.id) {
        await _endCurrentSession(previousUser);
      }
      state = AuthState.authenticated(await _afterSignIn(user));
      return const GoogleSignInResult(GoogleSignInOutcome.signedIn);
    } on AuthException catch (error) {
      if (error.statusCode == 428) {
        return const GoogleSignInResult(GoogleSignInOutcome.needsNeighborhood);
      }
      return GoogleSignInResult(GoogleSignInOutcome.failed, error.message);
    } catch (error) {
      return GoogleSignInResult(GoogleSignInOutcome.failed, _message(error));
    }
  }

  /// Envía otra vez el código al correo de la cuenta actual. null = enviado.
  Future<String?> resendVerificationCode() async {
    final email = state.user?.email;
    if (email == null) return 'No encontramos el correo de tu cuenta.';
    try {
      await _repository.sendVerificationCode(email);
      return null;
    } catch (error) {
      return _message(error);
    }
  }

  /// Confirma el correo con el código. null = listo (la app sigue sola).
  Future<String?> verifyEmail(String code) async {
    final email = state.user?.email;
    if (email == null) return 'No encontramos el correo de tu cuenta.';
    try {
      final user = await _repository.verifyEmail(email: email, code: code);
      state = AuthState.authenticated(user);
      return null;
    } catch (error) {
      return _message(error);
    }
  }

  /// "Olvidé mi contraseña": pide el código. null = enviado.
  Future<String?> requestPasswordReset(String email) async {
    try {
      await _repository.requestPasswordReset(email);
      return null;
    } catch (error) {
      return _message(error);
    }
  }

  /// Cambia la contraseña con el código y entra. null = listo.
  Future<String?> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    final previousUser = state.user;
    try {
      final user = await _repository.resetPassword(
        email: email,
        code: code,
        newPassword: newPassword,
      );
      if (previousUser != null && previousUser.id != user.id) {
        await _endCurrentSession(previousUser);
      }
      state = AuthState.authenticated(await _afterSignIn(user));
      return null;
    } catch (error) {
      return _message(error);
    }
  }

  Future<void> logout() async {
    final currentUser = state.user;
    state = const AuthState.loading();
    try {
      await _endCurrentSession(currentUser);
      state = const AuthState.unauthenticated();
    } catch (error) {
      state = AuthState(status: AuthStatus.error, message: _message(error));
    }
  }

  /// Borra la cuenta en el servidor y luego los datos del celular. null = listo.
  Future<String?> deleteAccount() async {
    final currentUser = state.user;
    final tenantId = currentUser?.tenantId;
    if (currentUser == null || tenantId == null) {
      return 'No hay una sesión iniciada.';
    }
    try {
      await _repository.deleteAccount(tenantId: tenantId);
    } catch (error) {
      return _message(error);
    }
    // La cuenta ya no existe: se borra todo del celular, también lo pendiente.
    try {
      await _endCurrentSession(currentUser);
    } catch (_) {
      // Aunque falle la limpieza local, la cuenta ya se borró: se sale igual.
    }
    state = const AuthState.unauthenticated();
    return null;
  }

  Future<void> expireSession() async {
    if (state.status == AuthStatus.unauthenticated ||
        state.status == AuthStatus.loading) {
      return;
    }
    final currentUser = state.user;
    state = const AuthState.loading();
    try {
      await _endCurrentSession(currentUser, keepPendingData: true);
      state = const AuthState.unauthenticated();
    } catch (error) {
      state = AuthState(
        status: AuthStatus.error,
        message: 'No se pudo cerrar la sesión vencida: ${_message(error)}',
      );
    }
  }

  Future<NeighborhoodProvisionEntity?> createNeighborhood({
    required String neighborhoodName,
    String? existingJoinCode,
    required String adminFullName,
    required String adminEmail,
    required String adminPassword,
    required double centerLat,
    required double centerLng,
  }) async {
    final currentUser = state.user;
    if (currentUser == null || currentUser.role != UserRole.superAdmin) {
      state = AuthState(
        status: AuthStatus.error,
        user: currentUser,
        message: 'Solo el superadministrador puede crear barrios',
      );
      return null;
    }
    try {
      return await _repository.createNeighborhood(
        neighborhoodName: neighborhoodName,
        existingJoinCode: existingJoinCode,
        adminFullName: adminFullName,
        adminEmail: adminEmail,
        adminPassword: adminPassword,
        centerLat: centerLat,
        centerLng: centerLng,
      );
    } catch (error) {
      state = AuthState(
        status: AuthStatus.error,
        user: currentUser,
        message: _message(error),
      );
      return null;
    }
  }

  @override
  void dispose() {
    unawaited(_sessionExpiredSubscription.cancel());
    super.dispose();
  }
}

enum GoogleSignInOutcome { signedIn, needsNeighborhood, failed }

class GoogleSignInResult {
  const GoogleSignInResult(this.outcome, [this.message]);

  final GoogleSignInOutcome outcome;

  /// Mensaje para el vecino cuando [outcome] es [GoogleSignInOutcome.failed].
  final String? message;
}
