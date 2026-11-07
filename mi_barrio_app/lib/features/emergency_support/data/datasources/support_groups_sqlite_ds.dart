import '../../../../core/database_sqlite/sqlite_database.dart';
import '../../../../shared/local_distance.dart';
import '../models/support_group_model.dart';

/// Grupos de apoyo guardados en el teléfono (llegan en el pull de /sync).
/// Funciona 100 % sin internet.
///
/// Uso en pantalla (sección "Grupos de apoyo" en emergencia):
/// ```dart
/// final grupos = await SupportGroupsSqliteDatasource()
///     .activeGroups(session.tenantId, lat: session.centerLat, lng: session.centerLng);
/// ```
class SupportGroupsSqliteDatasource {
  SupportGroupsSqliteDatasource({LocalDatabase? database})
      : _db = database ?? LocalDatabase.instance;

  final LocalDatabase _db;

  /// Grupos activos del barrio. Con [lat]/[lng]: del más cercano al más lejano
  /// (los que no tienen ubicación van al final); sin ubicación: por nombre.
  /// [groupType] filtra por tipo (ej. `SupportGroupType.albergue`).
  Future<List<SupportGroupModel>> activeGroups(
    String tenantId, {
    double? lat,
    double? lng,
    String? groupType,
  }) async {
    final where = StringBuffer('tenant_id = ? AND is_deleted = 0 AND is_active = 1');
    final args = <Object?>[tenantId];
    if (groupType != null) {
      where.write(' AND group_type = ?');
      args.add(groupType);
    }
    final db = await _db.database;
    final rows = await db.query(
      SupportGroupModel.table,
      where: where.toString(),
      whereArgs: args,
      orderBy: 'name COLLATE NOCASE ASC',
    );
    final groups = rows.map(SupportGroupModel.fromSqlite).toList();
    if (lat == null || lng == null) return groups;

    final withDistance = [
      for (final g in groups)
        g.withDistance(
          g.lat == null || g.lng == null ? null : LocalDistance.km(lat, lng, g.lat!, g.lng!),
        ),
    ];
    withDistance.sort((a, b) {
      final da = a.distanceKm;
      final db = b.distanceKm;
      if (da == null && db == null) return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      if (da == null) return 1;
      if (db == null) return -1;
      return da.compareTo(db);
    });
    return withDistance;
  }

  /// Cuántos grupos activos hay (para mostrar la sección solo si hay alguno).
  Future<int> countActive(String tenantId) async {
    final db = await _db.database;
    final r = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM ${SupportGroupModel.table} '
      'WHERE tenant_id = ? AND is_deleted = 0 AND is_active = 1',
      [tenantId],
    );
    return (r.first['c'] as int?) ?? 0;
  }
}
