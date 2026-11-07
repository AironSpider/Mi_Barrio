import '../../features/emergency_support/data/models/vulnerable_report_model.dart';
import '../../features/emergency_support/domain/entities/vulnerable_report_entity.dart';
import '../../features/proximity_services/data/models/service_model.dart';
import '../../features/solidarity_network/data/models/solidarity_post_model.dart';
import 'sqlite_database.dart';

/// Cuántos registros tiene el vecino en cada pestaña de "Mi historial".
class HistoryCounts {
  const HistoryCounts({
    required this.services,
    required this.posts,
    required this.sos,
  });

  final int services;
  final int posts;
  final int sos;

  int get total => services + posts + sos;
}

/// "Mi historial": lo que publicó el vecino, leído solo de SQLite (sin red).
///
/// Incluye lo que todavía no se sube (PENDING / FAILED), para que la pantalla
/// muestre el chip de sincronización de cada ítem. Nunca muestra borrados ni
/// datos de otro barrio. Orden: lo más reciente primero.
class HistoryDao {
  HistoryDao({LocalDatabase? database})
      : _db = database ?? LocalDatabase.instance;

  final LocalDatabase _db;

  /// Oficios que ofrezco (como comerciante).
  Future<List<LocalServiceModel>> myServices(String tenantId, String userId) async {
    final rows = await _mine(LocalServiceModel.table, 'provider_user_id', tenantId, userId);
    return rows.map(LocalServiceModel.fromSqlite).toList(growable: false);
  }

  /// Favores que publiqué en el muro (incluye los COMPLETADO).
  Future<List<SolidarityPostModel>> myPosts(String tenantId, String userId) async {
    final rows = await _mine(SolidarityPostModel.table, 'author_user_id', tenantId, userId);
    return rows.map(SolidarityPostModel.fromSqlite).toList(growable: false);
  }

  /// Pedidos de ayuda (SOS) que hice.
  Future<List<VulnerableReport>> mySos(String tenantId, String userId) async {
    final rows = await _mine(VulnerableReportModel.table, 'reporter_user_id', tenantId, userId);
    return rows.map(VulnerableReportModel.fromSqlite).toList(growable: false);
  }

  /// Contador para las 3 pestañas (Mis servicios / Mis favores / Mis SOS).
  Future<HistoryCounts> counts(String tenantId, String userId) async {
    final db = await _db.database;
    Future<int> count(String table, String ownerColumn) async {
      final r = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM $table '
        'WHERE tenant_id = ? AND $ownerColumn = ? AND is_deleted = 0',
        [tenantId, userId],
      );
      return (r.first['c'] as int?) ?? 0;
    }

    return HistoryCounts(
      services: await count(LocalServiceModel.table, 'provider_user_id'),
      posts: await count(SolidarityPostModel.table, 'author_user_id'),
      sos: await count(VulnerableReportModel.table, 'reporter_user_id'),
    );
  }

  Future<List<Map<String, Object?>>> _mine(
    String table,
    String ownerColumn,
    String tenantId,
    String userId,
  ) async {
    final db = await _db.database;
    return db.query(
      table,
      where: 'tenant_id = ? AND $ownerColumn = ? AND is_deleted = 0',
      whereArgs: [tenantId, userId],
      orderBy: 'updated_at DESC',
    );
  }
}
