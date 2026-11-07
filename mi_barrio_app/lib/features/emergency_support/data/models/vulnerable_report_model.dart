import '../../../../core/database_sqlite/sqlite_tables.dart';
import '../../domain/entities/vulnerable_report_entity.dart';

/// Conversión entre la entidad, SQLite (0/1 + sync_status) y el payload de /sync/push.
class VulnerableReportModel {
  VulnerableReportModel._();

  static const table = 'vulnerable_reports';

  static Map<String, Object?> toSqlite(VulnerableReport r, {required String syncStatus}) => {
    'id': r.id,
    'tenant_id': r.tenantId,
    'reporter_user_id': r.reporterUserId,
    'urgency_level': r.urgencyLevel,
    'vulnerability_type': r.vulnerabilityType,
    'description': r.description,
    'lat': r.lat,
    'lng': r.lng,
    'status': r.status,
    'helper_user_id': r.helperUserId,
    'is_deleted': 0,
    'updated_at': r.updatedAt,
    'sync_status': syncStatus,
  };

  /// `tenant_id` viaja en el header. El servidor valida que `reporter_user_id`
  /// sea quien envía; si es otro vecino, solo acepta "voy en camino".
  static Map<String, Object?> toSyncPayload(VulnerableReport r) => {
    'id': r.id,
    'reporter_user_id': r.reporterUserId,
    'urgency_level': r.urgencyLevel,
    'vulnerability_type': r.vulnerabilityType,
    'description': r.description,
    'lat': r.lat,
    'lng': r.lng,
    'status': r.status,
    'helper_user_id': r.helperUserId,
    'is_deleted': false,
    'updated_at': r.updatedAt,
  };

  static VulnerableReport fromSqlite(Map<String, Object?> row) => VulnerableReport(
    id: row['id'] as String,
    tenantId: row['tenant_id'] as String,
    reporterUserId: row['reporter_user_id'] as String,
    urgencyLevel: row['urgency_level'] as String,
    vulnerabilityType: row['vulnerability_type'] as String,
    description: row['description'] as String? ?? '',
    lat: (row['lat'] as num).toDouble(),
    lng: (row['lng'] as num).toDouble(),
    status: row['status'] as String? ?? ReportStatus.pendienteApoyo,
    helperUserId: row['helper_user_id'] as String?,
    updatedAt: row['updated_at'] as String,
    isPending: row['sync_status'] == SqliteTables.syncPending,
  );
}
