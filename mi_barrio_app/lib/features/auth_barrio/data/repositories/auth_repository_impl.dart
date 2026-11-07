import '../../../../core/auth/auth_session_store.dart';
import '../../domain/entities/user_entity.dart';
import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_datasource.dart';
import '../models/user_model.dart';

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl({
    AuthRemoteDatasource? remote,
    AuthSessionStore? sessionStore,
  }) : _remote = remote ?? AuthRemoteDatasource(),
       _sessionStore = sessionStore ?? AuthSessionStore.instance;

  final AuthRemoteDatasource _remote;
  final AuthSessionStore _sessionStore;

  @override
  Future<UserEntity> login({
    required String email,
    required String password,
  }) async {
    final response = await _remote.login(email: email, password: password);
    return _persistResponse(response);
  }

  @override
  Future<UserEntity> register({
    required String fullName,
    required String email,
    required String password,
    required UserRole role,
    required String joinCode,
  }) async {
    final response = await _remote.register(
      fullName: fullName,
      email: email,
      password: password,
      role: role.apiValue,
      joinCode: joinCode,
    );
    return _persistResponse(response);
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

  @override
  Future<UserEntity?> restoreSession() async {
    final storedJson = await _sessionStore.read();
    if (storedJson == null) return null;
    final cachedUser = UserModel.fromStoredJson(storedJson);
    try {
      final remoteUser = await _remote.getCurrentUser(cachedUser.token);
      final verified = UserModel.fromJson({
        ...remoteUser,
        'access_token': cachedUser.token,
      });
      await _sessionStore.save(verified.toJson());
      return verified;
    } on AuthException catch (error) {
      if (error.statusCode == 401 || error.statusCode == 403) {
        await _sessionStore.clear();
        return null;
      }
      if (error.statusCode == null) return cachedUser;
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
}
