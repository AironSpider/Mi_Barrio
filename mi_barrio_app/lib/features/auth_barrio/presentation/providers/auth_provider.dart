import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/auth_session_store.dart';
import '../../../../core/sync_manager/sync_coordinator.dart';
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
