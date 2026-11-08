import '../../../core/database_sqlite/record_validation.dart';
import '../../../core/database_sqlite/sqlite_database.dart';
import '../../../core/database_sqlite/sqlite_tables.dart';
import '../../../core/database_sqlite/sync_outbox_dao.dart';
import 'tutorial_progress.dart';
import 'user_profile_model.dart';

/// Guarda y lee el perfil del vecino en SQLite ("Mi Perfil y Cuenta").
/// "Guardar cambios" escribe con `PENDING` y encola un UPSERT para el sync.
class ProfileLocalStorage {
  ProfileLocalStorage({LocalDatabase? database, SyncOutboxDao? outboxDao})
      : _db = database ?? LocalDatabase.instance,
        _outboxDao = outboxDao ?? SyncOutboxDao();

  final LocalDatabase _db;
  final SyncOutboxDao _outboxDao;

  static final _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');
  static final _phone = RegExp(r'^\+?[0-9 ]{6,20}$');

  Future<UserProfileModel?> getProfile(String userId) async {
    final db = await _db.database;
    final rows = await db.query(UserProfileModel.table,
        where: 'id = ? AND is_deleted = 0', whereArgs: [userId], limit: 1);
    return rows.isEmpty ? null : UserProfileModel.fromSqlite(rows.first);
  }

  /// Guarda el perfil (crear o editar). Lanza [ArgumentError] si hay datos inválidos.
  Future<UserProfileModel> saveProfile({
    required String userId,
    required String tenantId,
    required String fullName,
    required double homeLat,
    required double homeLng,
    String phone = '',
    String? addressReference,
    String? email,
    String? emailContacto,
    String? whatsapp,
    String? facebookUrl,
    String? instagramUrl,
    String? photoB64,
    String? publisherType,
    String? publisherCategory,
    String? publisherName,
    bool? tutorialCompleted,
  }) async {
    RecordValidation.uuid(userId, 'userId');
    RecordValidation.uuid(tenantId, 'tenantId');
    RecordValidation.coordinates(homeLat, homeLng);
    final name = RecordValidation.requiredText(fullName, 'fullName', maxLength: 150);

    String? clean(String? v) => (v == null || v.trim().isEmpty) ? null : v.trim();
    final cleanPhone = clean(phone) ?? '';
    if (cleanPhone.isNotEmpty && !_phone.hasMatch(cleanPhone)) {
      throw ArgumentError.value(phone, 'phone', 'Teléfono inválido');
    }
    final cleanEmail = clean(email);
    if (cleanEmail != null && !_email.hasMatch(cleanEmail)) {
      throw ArgumentError.value(email, 'email', 'Correo inválido');
    }
    final cleanEmailContacto = clean(emailContacto);
    if (cleanEmailContacto != null &&
        (cleanEmailContacto.length > 254 || !_email.hasMatch(cleanEmailContacto))) {
      throw ArgumentError.value(emailContacto, 'emailContacto', 'Correo de contacto inválido');
    }
    final cleanWhatsapp = clean(whatsapp);
    if (cleanWhatsapp != null && !_phone.hasMatch(cleanWhatsapp)) {
      throw ArgumentError.value(whatsapp, 'whatsapp', 'WhatsApp inválido');
    }
    for (final entry in {'facebookUrl': facebookUrl, 'instagramUrl': instagramUrl}.entries) {
      final url = clean(entry.value);
      if (url != null && !url.startsWith('https://')) {
        throw ArgumentError.value(entry.value, entry.key, 'Debe empezar con https://');
      }
    }
    final type = clean(publisherType);
    if (type != null) RecordValidation.oneOf(type, PublisherType.values, 'publisherType');

    final previous = await getProfile(userId);
    // Si ya vio el tutorial (aunque la fila no lo tenga), guardar el perfil no lo
    // "des-marca": el payload completo viaja al servidor.
    final tutorialSeen = (previous?.tutorialCompleted ?? false) ||
        await TutorialProgress(database: _db, outboxDao: _outboxDao).localFlag(userId);
    final profile = UserProfileModel(
      id: userId,
      tenantId: tenantId,
      fullName: name,
      phone: cleanPhone,
      addressReference: clean(addressReference),
      homeLat: homeLat,
      homeLng: homeLng,
      // El rol nunca se cambia desde el perfil: se conserva el que había.
      role: previous?.role ?? UserRole.vecino,
      tutorialCompleted: tutorialCompleted ?? tutorialSeen,
      email: cleanEmail,
      emailContacto: cleanEmailContacto,
      whatsapp: cleanWhatsapp,
      facebookUrl: clean(facebookUrl),
      instagramUrl: clean(instagramUrl),
      photoB64: photoB64 ?? previous?.photoB64,
      publisherType: type,
      publisherCategory: clean(publisherCategory),
      publisherName: type == null || type == 'PERSONA_NATURAL' ? null : clean(publisherName),
      updatedAt: DateTime.now().toUtc().toIso8601String(),
      syncStatus: SqliteTables.syncPending,
    );

    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.rawInsert(
        'INSERT OR REPLACE INTO ${UserProfileModel.table} '
        '(${profile.toSqlite().keys.join(', ')}) '
        'VALUES (${List.filled(profile.toSqlite().length, '?').join(', ')})',
        profile.toSqlite().values.toList(),
      );
      await _outboxDao.queueMutation(
        tenantId: tenantId,
        targetTable: UserProfileModel.table,
        recordId: userId,
        operation: OutboxOperation.upsert,
        payload: profile.toSyncPayload(),
        executor: txn,
      );
    });
    return profile;
  }
}
