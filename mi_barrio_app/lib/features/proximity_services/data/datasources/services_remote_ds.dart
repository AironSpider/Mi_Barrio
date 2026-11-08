import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../../core/database_sqlite/sqlite_database.dart';
import '../../../../core/database_sqlite/sqlite_tables.dart';
import '../../../../core/network/api_client.dart';
import '../models/endorsement_model.dart';
import 'endorsements_sqlite_ds.dart';

/// Lista de calificaciones de un servicio lista para la hoja de detalle.
class ServiceReviews {
  const ServiceReviews({
    required this.items,
    required this.fromServer,
    this.withPhoto = const {},
    this.photoFlagsKnown = true,
  });

  /// Más recientes primero. Las calificaciones mías aún sin subir (PENDING)
  /// aparecen con su estado local, aunque el servidor tenga una versión vieja.
  final List<EndorsementModel> items;

  /// false = sin internet (o el servidor falló): se muestra lo guardado en el teléfono.
  final bool fromServer;

  /// Ids de calificaciones que tienen foto (se pide aparte con
  /// [ServicesRemoteDatasource.fetchEndorsementPhoto]).
  final Set<String> withPhoto;

  /// false = el servidor no dice qué calificaciones tienen foto (no manda
  /// `has_photo`): la pantalla puede pedir la foto al abrir cada una y
  /// [ServicesRemoteDatasource.fetchEndorsementPhoto] devuelve null si no hay.
  final bool photoFlagsKnown;

  /// Promedio de lo que se ve en la lista (null si nadie puso estrellas).
  double? get average {
    final stars = [
      for (final e in items)
        if (e.rating != null) e.rating!,
    ];
    if (stars.isEmpty) return null;
    return stars.reduce((a, b) => a + b) / stars.length;
  }
}

/// Lecturas del servidor para el directorio de oficios.
///
/// Contrato con el backend (Dev 1, Sprint 10):
/// - `GET /api/v1/services/{id}/endorsements` → lista (o `{"items": [...]}`) de
///   `{id, service_id, endorser_user_id, rating, short_comment, has_photo, updated_at}`.
///   **Sin** `photo_b64`, para que la lista pese poco.
/// - `GET /api/v1/endorsements/{id}/photo` → `{"photo_b64": "..."}`.
///
/// Si no hay red o el endpoint aún no existe (404), cae a SQLite: la app
/// nunca muestra un error por esto.
class ServicesRemoteDatasource {
  ServicesRemoteDatasource({
    ApiClient? api,
    LocalDatabase? database,
    EndorsementsSqliteDatasource? local,
  }) : _api = api ?? ApiClient(),
       _db = database ?? LocalDatabase.instance,
       _local = local ?? EndorsementsSqliteDatasource();

  final ApiClient _api;
  final LocalDatabase _db;
  final EndorsementsSqliteDatasource _local;

  /// Calificaciones del servicio: del servidor si hay red (y se guardan en
  /// SQLite para verlas luego sin red); si no, las del teléfono.
  Future<ServiceReviews> fetchEndorsements({
    required String tenantId,
    required String serviceId,
  }) async {
    List<Map<String, dynamic>> remote;
    try {
      final response = await _api.get(
        '/api/v1/services/$serviceId/endorsements',
        tenantId,
      );
      if (response.statusCode != 200) {
        return await _offline(tenantId, serviceId);
      }
      remote = _rows(jsonDecode(response.body));
    } catch (_) {
      return _offline(tenantId, serviceId);
    }

    final withPhoto = <String>{};
    final fromServer = <EndorsementModel>[];
    var photoFlagsKnown = true;
    for (final raw in remote) {
      final parsed = _parse(raw, tenantId, serviceId);
      if (parsed == null) continue;
      fromServer.add(parsed);
      if (!raw.containsKey('has_photo')) photoFlagsKnown = false;
      if (raw['has_photo'] == true) withPhoto.add(parsed.id);
    }
    await _cache(fromServer);
    await _forgetRemovedOnServer(tenantId, serviceId, fromServer);

    // Lo local manda si tiene cambios sin subir (mi calificación editada offline).
    final local = await _local.listForService(tenantId, serviceId);
    final pendingLocal = {
      for (final e in local)
        if (e.syncStatus != SqliteTables.syncSynced) e.id: e,
    };
    final merged = <String, EndorsementModel>{
      for (final e in fromServer)
        if (!e.isDeleted) e.id: e,
    };
    for (final e in pendingLocal.values) {
      merged[e.id] = e;
      if (e.photoB64 != null) withPhoto.add(e.id);
    }
    final items = merged.values.where((e) => !e.isDeleted).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return ServiceReviews(
      items: items,
      fromServer: true,
      withPhoto: withPhoto,
      photoFlagsKnown: photoFlagsKnown,
    );
  }

  /// El servidor no lista las calificaciones borradas: si una copia guardada
  /// (SYNCED) ya no viene en la lista, se borró allá y se oculta también aquí.
  /// Nunca toca mis cambios aún sin subir.
  Future<void> _forgetRemovedOnServer(
    String tenantId,
    String serviceId,
    List<EndorsementModel> fromServer,
  ) async {
    final keep = {for (final e in fromServer) e.id};
    final db = await _db.database;
    final cached = await db.query(
      EndorsementModel.table,
      columns: ['id'],
      where: 'tenant_id = ? AND service_id = ? AND is_deleted = 0 AND sync_status = ?',
      whereArgs: [tenantId, serviceId, SqliteTables.syncSynced],
    );
    final gone = [
      for (final r in cached)
        if (!keep.contains(r['id'])) r['id'] as String,
    ];
    if (gone.isEmpty) return;
    final placeholders = List.filled(gone.length, '?').join(',');
    await db.update(
      EndorsementModel.table,
      {'is_deleted': 1},
      where: 'id IN ($placeholders)',
      whereArgs: gone,
    );
  }

  /// Fotos de un servicio (base64). Vacío si no tiene o no hay red.
  Future<List<String>> fetchServicePhotos({
    required String tenantId,
    required String serviceId,
  }) async {
    try {
      final response = await _api.get(
        '/api/v1/services/$serviceId/photos',
        tenantId,
      );
      if (response.statusCode != 200) return const [];
      final body = jsonDecode(response.body);
      final photos = body is Map ? body['photos'] : null;
      if (photos is! List) return const [];
      return photos
          .whereType<String>()
          .where((p) => p.isNotEmpty)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  /// Foto de una calificación (base64) o null si no tiene / no hay red.
  Future<String?> fetchEndorsementPhoto({
    required String tenantId,
    required String endorsementId,
  }) async {
    try {
      final response = await _api.get(
        '/api/v1/endorsements/$endorsementId/photo',
        tenantId,
      );
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body);
      final photo = body is Map ? body['photo_b64'] : null;
      if (photo is! String || photo.isEmpty) return null;
      // Mismo tope que al guardar: una foto gigante no entra a la memoria.
      if (photo.length > EndorsementModel.maxPhotoB64Length * 2) return null;
      return photo;
    } catch (_) {
      return null;
    }
  }

  Future<ServiceReviews> _offline(String tenantId, String serviceId) async {
    final local = await _local.listForService(tenantId, serviceId);
    return ServiceReviews(
      items: local,
      fromServer: false,
      withPhoto: {
        for (final e in local)
          if (e.photoB64 != null) e.id,
      },
    );
  }

  static List<Map<String, dynamic>> _rows(Object? body) {
    final list = body is Map ? body['items'] : body;
    if (list is! List) return const [];
    return list.whereType<Map<String, dynamic>>().toList(growable: false);
  }

  /// Convierte una fila del servidor. Ignora las de otro servicio o mal formadas.
  static EndorsementModel? _parse(
    Map<String, dynamic> raw,
    String tenantId,
    String serviceId,
  ) {
    final id = raw['id'];
    final endorser = raw['endorser_user_id'];
    final updatedAt = raw['updated_at'];
    if (id is! String || endorser is! String || updatedAt is! String) {
      return null;
    }
    if (raw['service_id'] != null && raw['service_id'] != serviceId) {
      return null;
    }
    if (raw['tenant_id'] != null && raw['tenant_id'] != tenantId) return null;
    final rating = raw['rating'];
    final comment = raw['short_comment'];
    final name = raw['endorser_name'];
    return EndorsementModel(
      id: id,
      tenantId: tenantId,
      serviceId: serviceId,
      endorserUserId: endorser,
      rating: rating is int && rating >= 1 && rating <= 5 ? rating : null,
      shortComment: comment is String && comment.isNotEmpty ? comment : null,
      isDeleted: raw['is_deleted'] == true,
      updatedAt: updatedAt,
      syncStatus: SqliteTables.syncSynced,
      endorserName: name is String && name.trim().isNotEmpty
          ? name.trim()
          : null,
    );
  }

  /// Guarda en SQLite lo que llegó del servidor, sin pisar:
  /// - cambios míos aún sin subir (PENDING / FAILED), ni
  /// - la foto que ya tenga guardada el teléfono.
  Future<void> _cache(List<EndorsementModel> rows) async {
    if (rows.isEmpty) return;
    final db = await _db.database;
    await db.transaction((txn) async {
      for (final e in rows) {
        final existing = await txn.query(
          EndorsementModel.table,
          columns: ['sync_status'],
          where: 'id = ?',
          whereArgs: [e.id],
          limit: 1,
        );
        if (existing.isEmpty) {
          await txn.insert(
            EndorsementModel.table,
            e.toSqlite(),
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        } else if (existing.first['sync_status'] == SqliteTables.syncSynced) {
          await txn.update(
            EndorsementModel.table,
            {
              'rating': e.rating,
              'short_comment': e.shortComment,
              'is_deleted': e.isDeleted ? 1 : 0,
              'updated_at': e.updatedAt,
              'endorser_name': e.endorserName,
            },
            where: 'id = ?',
            whereArgs: [e.id],
          );
        }
      }
    });
  }
}
