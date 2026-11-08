import '../../../../core/auth/auth_session_store.dart';
import '../../../../core/database_sqlite/sync_outbox_dao.dart';
import '../../../profile_me/data/profile_sync.dart';
import '../../domain/entities/user_entity.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_datasource.dart';
import '../models/user_model.dart';

/// Une el servidor ([AuthRemoteDatasource]) con la sesión guardada en el teléfono
/// ([AuthSessionStore]) y los datos locales pendientes de sincronizar.
class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl({
    AuthRemoteDatasource? remote,
    AuthSessionStore? sessionStore,
    ProfileSync? profileSync,
  }) : _remote = remote ?? AuthRemoteDatasource(),
       _sessionStore = sessionStore ?? AuthSessionStore.instance,
       _profileSync = profileSync ?? ProfileSync();

  final AuthRemoteDatasource _remote;
  final AuthSessionStore _sessionStore;
  final ProfileSync _profileSync;

  /// Tiempo máximo que el login espera el perfil completo; si no llega, se
  /// sigue con lo local (rol y nombre del login) y no se bloquea la entrada.
  static const profileWait = Duration(seconds: 4);

  @override
  Future<UserEntity> login({
    required String email,
    required String password,
  }) async {
    final response = await _remote.login(email: email, password: password);
    return _afterAuth(await _persistResponse(response), online: true);
  }

  /// Guarda en SQLite el perfil del propio vecino (rol real, nombre, tutorial).
  /// Sin esto, un COMERCIANTE no veía "Ofrecer servicio" y "Tú" salía vacío.
  /// Nunca hace fallar el login.
  Future<UserEntity> _afterAuth(UserEntity user, {required bool online}) async {
    final tenantId = user.tenantId;
    if (tenantId == null || user.role == UserRole.superAdmin) return user;
    try {
      final sync = _profileSync;
      await sync.seedFromLogin(
        userId: user.id,
        tenantId: tenantId,
        fullName: user.fullName,
        role: user.role.apiValue,
        centerLat: user.centerLat,
        centerLng: user.centerLng,
      );
      if (online) {
        await sync
            .refreshFromServer(tenantId: tenantId, userId: user.id)
            .timeout(profileWait, onTimeout: () => null);
      }
    } catch (_) {
      // Sin base local o sin red: la sesión sigue igual.
    }
    return user;
  }

  @override
  Future<UserEntity> register({
    required String fullName,
    required String email,
    required String password,
    required UserRole role,
    required String joinCode,
    required bool acceptedTerms,
  }) async {
    final response = await _remote.register(
      fullName: fullName,
      email: email,
      password: password,
      role: role.apiValue,
      joinCode: joinCode,
      acceptedTerms: acceptedTerms,
    );
    return _afterAuth(await _persistResponse(response), online: true);
  }

  @override
  Future<UserEntity> signInWithGoogle({
    required String idToken,
    String? joinCode,
    UserRole role = UserRole.vecino,
    bool acceptedTerms = false,
  }) async {
    final response = await _remote.googleLogin(
      idToken: idToken,
      joinCode: joinCode,
      role: role.apiValue,
      acceptedTerms: acceptedTerms,
    );
    return _afterAuth(await _persistResponse(response), online: true);
  }

  @override
  Future<String> sendVerificationCode(String email) =>
      _remote.sendVerificationCode(email);

  @override
  Future<UserEntity> verifyEmail({
    required String email,
    required String code,
  }) async {
    final response = await _remote.verifyEmail(email: email, code: code);
    return _afterAuth(await _persistResponse(response), online: true);
  }

  @override
  Future<UserEntity> setPassword(String password) async {
    final token = _sessionStore.token;
    if (token == null || token.isEmpty) {
      throw const AuthException(
        'Tu sesión venció. Vuelve a entrar con Google.',
      );
    }
    final response = await _remote.setPassword(
      token: token,
      password: password,
    );
    return _afterAuth(await _persistResponse(response), online: true);
  }

  @override
  Future<String> requestPasswordReset(String email) =>
      _remote.requestPasswordReset(email);

  @override
  Future<UserEntity> resetPassword({
    required String email,
    required String code,
    required String newPassword,
  }) async {
    final response = await _remote.resetPassword(
      email: email,
      code: code,
      newPassword: newPassword,
    );
    return _afterAuth(await _persistResponse(response), online: true);
  }

  Future<UserModel> _persistResponse(Map<String, dynamic> response) async {
    final userData = response['user'];
    if (userData is! Map<String, dynamic>) {
      throw const FormatException(
        'El servidor no devolvió los datos de usuario',
      );
    }
    final user = UserModel.fromJson({
      ...userData,
      'access_token': response['access_token'],
    });
    await _sessionStore.save(user.toJson());
    return user;
  }

  /// Cuánto se espera al servidor al abrir la app antes de entrar sin red.
  static const restoreTimeout = Duration(seconds: 8);

  @override
  Future<UserEntity?> restoreSession() async {
    final storedJson = await _sessionStore.read();
    if (storedJson == null) return null;
    final cachedUser = UserModel.fromStoredJson(storedJson);
    try {
      // Offline-first: si el servidor no contesta rápido (Render despertando,
      // señal débil en una emergencia), se entra con la sesión guardada en
      // vez de dejar al vecino hasta 90 s mirando un indicador. Si el token
      // venció, la próxima sincronización recibe 401 y cierra la sesión.
      final remoteUser = await _remote.getCurrentUser(
        cachedUser.token,
        timeout: restoreTimeout,
      );
      final verified = UserModel.fromJson({
        ...remoteUser,
        'access_token': cachedUser.token,
      });
      await _sessionStore.save(verified.toJson());
      return await _afterAuth(verified, online: true);
    } on AuthException catch (error) {
      if (error.statusCode == 401 || error.statusCode == 403) {
        // Sesión vencida: NO se borran los cambios hechos sin internet. Si la
        // misma persona vuelve a entrar, se suben; si entra otra, se descartan.
        try {
          final tenantId = cachedUser.tenantId;
          if (tenantId != null) {
            await keepPendingDataFor(tenantId: tenantId, userId: cachedUser.id);
          }
        } finally {
          await _sessionStore.clear();
        }
        // Cuenta suspendida: se avisa en la pantalla de ingreso por qué.
        if (error.message.toLowerCase().contains('suspendida')) rethrow;
        return null;
      }
      // Sin red o servidor caído / despertando (5xx, ej. Render free): entra
      // con lo guardado (offline-first) y solo se asegura la fila local.
      final status = error.statusCode;
      if (status == null || status >= 500) {
        return _afterAuth(cachedUser, online: false);
      }
      rethrow;
    }
  }

  @override
  Future<NeighborhoodProvisionEntity> createNeighborhood({
    required String neighborhoodName,
    String? existingJoinCode,
    required String adminFullName,
    required String adminEmail,
    required String adminPassword,
    required double centerLat,
    required double centerLng,
  }) {
    final token = _sessionStore.token;
    if (token == null || token.isEmpty) {
      throw StateError('Inicia sesión como superadministrador');
    }
    return _remote.createNeighborhood(
      token: token,
      neighborhoodName: neighborhoodName,
      existingJoinCode: existingJoinCode,
      adminFullName: adminFullName,
      adminEmail: adminEmail,
      adminPassword: adminPassword,
      centerLat: centerLat,
      centerLng: centerLng,
    );
  }

  @override
  Future<void> logout() => _sessionStore.clear();

  @override
  Future<void> deleteAccount({required String tenantId}) {
    final token = _sessionStore.token;
    if (token == null || token.isEmpty) {
      throw const AuthException(
        'Tu sesión venció. Vuelve a entrar e intenta de nuevo.',
      );
    }
    return _remote.deleteAccount(token: token, tenantId: tenantId);
  }

  @override
  Future<void> keepPendingDataFor({
    required String tenantId,
    required String userId,
  }) =>
      SyncOutboxDao().rememberPendingOwner(tenantId: tenantId, userId: userId);

  @override
  Future<void> reconcilePendingData(UserEntity user) async {
    final dao = SyncOutboxDao();
    final owner = await dao.readPendingOwner();
    if (owner == null) return;
    if (owner.userId != user.id || owner.tenantId != user.tenantId) {
      await dao.clearUserData(tenantId: owner.tenantId, userId: owner.userId);
    }
    await dao.forgetPendingOwner();
  }

  @override
  Future<void> purgeLocalUserData({
    required String tenantId,
    required String userId,
  }) {
    return SyncOutboxDao().clearUserData(tenantId: tenantId, userId: userId);
  }
}
