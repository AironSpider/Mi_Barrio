import '../entities/user_entity.dart';

abstract interface class AuthRepository {
  Future<UserEntity> login({required String email, required String password});

  Future<UserEntity> register({
    required String fullName,
    required String email,
    required String password,
    required UserRole role,
    required String joinCode,
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

  Future<void> purgeLocalUserData({
    required String tenantId,
    required String userId,
  });
}
