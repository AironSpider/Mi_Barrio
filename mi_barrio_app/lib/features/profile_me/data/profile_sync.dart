import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../core/database_sqlite/sqlite_database.dart';
import '../../../core/database_sqlite/sqlite_tables.dart';
import '../../../core/network/api_client.dart';
import 'tutorial_progress.dart';
import 'user_profile_model.dart';

/// Mantiene la fila `users` del propio vecino al día con el servidor.
///
/// Sin esto la app no sabía el ROL real (un COMERCIANTE no veía
/// "Ofrecer servicio") ni el nombre en "Tú", ni si ya vio el tutorial
/// en otro teléfono.
///
/// - [seedFromLogin]: sin red, con lo que devolvió el login.
/// - [refreshFromServer]: `GET /api/v1/users/me` (perfil completo).
///
/// Nunca pisa cambios del perfil hechos sin internet (PENDING / FAILED):
/// en ese caso solo actualiza el rol (lo decide el servidor) y la bandera
/// del tutorial (si alguno de los dos dice "visto", queda visto).
class ProfileSync {
  ProfileSync({LocalDatabase? database, ApiClient? api, TutorialProgress? tutorial})
      : _db = database ?? LocalDatabase.instance,
        _api = api ?? ApiClient(),
        _tutorial = tutorial ?? TutorialProgress(database: database);

  final LocalDatabase _db;
  final ApiClient _api;
  final TutorialProgress _tutorial;

  /// Fecha "muy vieja" para filas creadas desde el login: cualquier dato del
  /// servidor o del propio vecino es más nuevo.
  static const _seedUpdatedAt = '1970-01-01T00:00:00.000Z';

  /// Crea o corrige la fila local con los datos del login (rol, nombre, barrio).
  /// [role] es el valor del contrato: VECINO, COMERCIANTE, ADMIN_BARRIO.
  Future<void> seedFromLogin({
    required String userId,
    required String tenantId,
    required String fullName,
    required String role,
    double? centerLat,
    double? centerLng,
  }) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      final row = await _row(txn, userId);
      if (row == null) {
        final done = await TutorialProgress.localFlagIn(txn, userId);
        await txn.insert(
          UserProfileModel.table,
          UserProfileModel(
            id: userId,
            tenantId: tenantId,
            fullName: fullName.trim().isEmpty ? 'Vecino' : fullName.trim(),
            homeLat: centerLat ?? 0,
            homeLng: centerLng ?? 0,
            role: role,
            tutorialCompleted: done,
            updatedAt: _seedUpdatedAt,
            syncStatus: SqliteTables.syncSynced,
          ).toSqlite(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        return;
      }
      final synced = row['sync_status'] == SqliteTables.syncSynced;
      await txn.update(
        UserProfileModel.table,
        {
          'role': role,
          if (synced && fullName.trim().isNotEmpty) 'full_name': fullName.trim(),
        },
        where: 'id = ?',
        whereArgs: [userId],
      );
    });
  }

  /// Trae el perfil completo del servidor. Devuelve el perfil guardado o null
  /// si no hay red / el servidor falló (la app sigue con lo local).
  Future<UserProfileModel?> refreshFromServer({
    required String tenantId,
    required String userId,
  }) async {
    Map<String, dynamic> body;
    try {
      final response = await _api.get('/api/v1/users/me', tenantId);
      if (response.statusCode != 200) return null;
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) return null;
      body = decoded;
    } catch (_) {
      return null;
    }
    if (body['id'] != userId || body['tenant_id'] != tenantId) return null;

    final server = _fromServer(body, tenantId);
    if (server == null) return null;

    final db = await _db.database;
    return db.transaction((txn) async {
      final localDone = await TutorialProgress.localFlagIn(txn, userId);
      final row = await _row(txn, userId);
      final rowDone = row?['tutorial_completed'] == 1;
      final done = server.tutorialCompleted || localDone || rowDone;

      if (done) await _tutorial.rememberLocally(txn, userId);
      // El teléfono sabe que lo vio y el servidor no (ej. se cerró sesión antes
      // de subirlo): se vuelve a enviar.
      if (done && !server.tutorialCompleted) {
        await _tutorial.queueServerUpdate(
          txn,
          tenantId: tenantId,
          userId: userId,
          updatedAt: DateTime.now().toUtc().toIso8601String(),
        );
      }

      final hasLocalEdits = row != null && row['sync_status'] != SqliteTables.syncSynced;
      if (hasLocalEdits) {
        await txn.update(
          UserProfileModel.table,
          {'role': server.role, 'tutorial_completed': done ? 1 : 0},
          where: 'id = ?',
          whereArgs: [userId],
        );
        return UserProfileModel.fromSqlite((await _row(txn, userId))!);
      }

      final saved = UserProfileModel(
        id: server.id,
        tenantId: tenantId,
        fullName: server.fullName,
        phone: server.phone,
        addressReference: server.addressReference,
        homeLat: server.homeLat,
        homeLng: server.homeLng,
        role: server.role,
        tutorialCompleted: done,
        email: server.email,
        emailContacto: server.emailContacto,
        whatsapp: server.whatsapp,
        facebookUrl: server.facebookUrl,
        instagramUrl: server.instagramUrl,
        photoB64: server.photoB64,
        publisherType: server.publisherType,
        publisherCategory: server.publisherCategory,
        publisherName: server.publisherName,
        updatedAt: server.updatedAt,
        syncStatus: SqliteTables.syncSynced,
      );
      await txn.insert(UserProfileModel.table, saved.toSqlite(),
          conflictAlgorithm: ConflictAlgorithm.replace);
      return saved;
    });
  }

  static Future<Map<String, Object?>?> _row(DatabaseExecutor db, String userId) async {
    final rows = await db.query(UserProfileModel.table,
        where: 'id = ?', whereArgs: [userId], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  static UserProfileModel? _fromServer(Map<String, dynamic> j, String tenantId) {
    final name = j['full_name'];
    final role = j['role'];
    final lat = j['home_lat'];
    final lng = j['home_lng'];
    final updatedAt = j['updated_at'];
    if (name is! String || role is! String || lat is! num || lng is! num || updatedAt is! String) {
      return null;
    }
    String? text(String key) {
      final v = j[key];
      return v is String && v.trim().isNotEmpty ? v : null;
    }

    return UserProfileModel(
      id: j['id'] as String,
      tenantId: tenantId,
      fullName: name,
      phone: j['phone'] is String ? j['phone'] as String : '',
      addressReference: text('address_reference'),
      homeLat: lat.toDouble(),
      homeLng: lng.toDouble(),
      role: role,
      tutorialCompleted: j['tutorial_completed'] == true,
      email: text('email'),
      emailContacto: text('email_contacto'),
      whatsapp: text('whatsapp'),
      facebookUrl: text('facebook_url'),
      instagramUrl: text('instagram_url'),
      photoB64: text('photo_b64'),
      publisherType: text('publisher_type'),
      publisherCategory: text('publisher_category'),
      publisherName: text('publisher_name'),
      updatedAt: updatedAt,
      syncStatus: SqliteTables.syncSynced,
    );
  }
}
