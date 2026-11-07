import 'package:flutter_test/flutter_test.dart';
import 'package:mi_barrio_app/features/auth_barrio/data/models/user_model.dart';
import 'package:mi_barrio_app/features/auth_barrio/domain/entities/user_entity.dart';
import 'package:mi_barrio_app/features/auth_barrio/domain/repositories/auth_repository.dart';
import 'package:mi_barrio_app/features/auth_barrio/presentation/providers/auth_provider.dart';

void main() {
  const userJson = {
    'id': 'user-1',
    'tenant_id': 'tenant-1',
    'full_name': 'Ana Vecina',
    'role': 'COMERCIANTE',
    'access_token': 'token-1',
    'tenant': {
      'id': 'tenant-1',
      'name': 'Barrio Centro',
      'join_code': 'CENTRO',
      'center_lat': -5.19,
      'center_lng': -80.63,
    },
  };

  test(
    'UserModel parses API payload and round-trips the persisted session',
    () {
      final user = UserModel.fromJson(userJson);
      final restored = UserModel.fromStoredJson(user.toJson());

      expect(user.role, UserRole.comerciante);
      expect(restored.id, 'user-1');
      expect(restored.tenantId, 'tenant-1');
      expect(restored.token, 'token-1');
      expect(restored.tenantName, 'Barrio Centro');
      expect(restored.centerLat, -5.19);
      expect(restored.centerLng, -80.63);
    },
  );

  test('UserModel rejects unsupported roles', () {
    expect(
      () => UserModel.fromJson({...userJson, 'role': 'ADMIN'}),
      throwsFormatException,
    );
  });

  test('UserModel supports platform administrators without a neighborhood', () {
    final user = UserModel.fromJson({
      'id': 'platform-admin-1',
      'full_name': 'Super Admin',
      'email': 'admin@example.com',
      'role': 'SUPER_ADMIN',
      'access_token': 'platform-token',
      'tenant_id': null,
      'tenant': null,
    });

    expect(user.role, UserRole.superAdmin);
    expect(user.tenantId, isNull);
    expect(user.tenantName, isNull);
    expect(
      AuthState.authenticated(user).status,
      AuthStatus.authenticatedSuperAdmin,
    );
  });

  test('administrator roles cannot be selected in public registration', () {
    expect(UserRole.values.where((role) => role.isSelfSelectable).toList(), [
      UserRole.vecino,
      UserRole.comerciante,
    ]);
  });

  test('AuthNotifier authenticates a user and exposes errors', () async {
    final notifier = AuthNotifier(_FakeAuthRepository());
    addTearDown(notifier.dispose);

    await notifier.login(email: 'ana@example.com', password: 'password123');
    expect(notifier.state.status, AuthStatus.authenticatedMerchant);
    expect(notifier.state.user?.id, 'user-1');

    await notifier.login(email: 'error@example.com', password: 'bad-password');
    expect(notifier.state.status, AuthStatus.error);
    expect(notifier.state.message, 'Credenciales inválidas');
  });
}

class _FakeAuthRepository implements AuthRepository {
  @override
  Future<UserEntity> login({
    required String email,
    required String password,
  }) async {
    if (email == 'error@example.com') {
      throw Exception('Credenciales inválidas');
    }
    return UserModel.fromJson({
      'id': 'user-1',
      'tenant_id': 'tenant-1',
      'full_name': 'Ana Vecina',
      'role': 'COMERCIANTE',
      'access_token': 'token-1',
      'tenant': const <String, dynamic>{},
    });
  }

  @override
  Future<UserEntity> register({
    required String fullName,
    required String email,
    required String password,
    required UserRole role,
    required String joinCode,
  }) async => throw UnimplementedError();

  @override
  Future<UserEntity?> restoreSession() async => null;

  @override
  Future<NeighborhoodProvisionEntity> createNeighborhood({
    required String neighborhoodName,
    String? existingJoinCode,
    required String adminFullName,
    required String adminEmail,
    required String adminPassword,
    required double centerLat,
    required double centerLng,
  }) async => throw UnimplementedError();

  @override
  Future<void> logout() async {}
}
