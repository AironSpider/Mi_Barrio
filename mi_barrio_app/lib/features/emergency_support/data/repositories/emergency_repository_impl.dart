import 'dart:async';

import '../../../../core/database_sqlite/local_id.dart';
import '../../../../core/database_sqlite/record_validation.dart';
import '../../../../core/database_sqlite/sqlite_database.dart';
import '../../../../core/database_sqlite/sqlite_tables.dart';
import '../../../../core/database_sqlite/sync_outbox_dao.dart';
import '../../../../core/sync_manager/sync_coordinator.dart';
import '../../domain/entities/vulnerable_report_entity.dart';
import '../../domain/repositories/emergency_repository.dart';
import '../models/vulnerable_report_model.dart';

/// SOS 100% offline: se guarda en SQLite (PENDING) + cola de sincronización,
/// en una sola transacción. El SyncCoordinator lo sube apenas haya señal.
class EmergencyRepositoryImpl implements EmergencyRepository {
  EmergencyRepositoryImpl({LocalDatabase? database, SyncOutboxDao? outboxDao})
    : _db = database ?? LocalDatabase.instance,
      _outboxDao = outboxDao ?? SyncOutboxDao();

  final LocalDatabase _db;
  final SyncOutboxDao _outboxDao;
  final StreamController<void> _localChanges = StreamController<void>.broadcast();

  /// Cambia cuando se guarda algo aquí o cuando termina un pull (datos de otros vecinos).
  @override
  Stream<void> get changes {
    late final StreamController<void> merged;
    StreamSubscription<void>? local;
    void onPull() => merged.add(null);
    merged = StreamController<void>.broadcast(
      onListen: () {
        local = _localChanges.stream.listen(merged.add);
        SyncCoordinator.instance.lastSuccess.addListener(onPull);
      },
      onCancel: () {
        unawaited(local?.cancel());
        SyncCoordinator.instance.lastSuccess.removeListener(onPull);
      },
    );
    return merged.stream;
  }

  @override
  Future<List<VulnerableReport>> activeReports(String tenantId) async {
    final db = await _db.database;
    final rows = await db.query(
      VulnerableReportModel.table,
      where: 'tenant_id = ? AND is_deleted = 0',
      whereArgs: [tenantId],
      orderBy: 'updated_at DESC',
    );
    return rows.map(VulnerableReportModel.fromSqlite).toList(growable: false);
  }

  @override
  Future<VulnerableReport> createSos({
    required String tenantId,
    required String reporterUserId,
    required String vulnerabilityType,
    required String urgencyLevel,
    required String description,
    required double lat,
    required double lng,
  }) async {
    RecordValidation.uuid(tenantId, 'tenantId');
    RecordValidation.uuid(reporterUserId, 'reporterUserId');
    RecordValidation.oneOf(vulnerabilityType, VulnerabilityType.values, 'vulnerabilityType');
    RecordValidation.oneOf(urgencyLevel, UrgencyLevel.values, 'urgencyLevel');
    RecordValidation.coordinates(lat, lng);
    final detail = description.trim();
    if (detail.length > 2000) {
      throw ArgumentError.value(description, 'description', 'Máximo 2000 caracteres');
    }

    final report = VulnerableReport(
      id: LocalId.generate(),
      tenantId: tenantId,
      reporterUserId: reporterUserId,
      urgencyLevel: urgencyLevel,
      vulnerabilityType: vulnerabilityType,
      // El servidor exige descripción: si el vecino no escribió nada, se usa el tipo.
      description: detail.isEmpty ? VulnerabilityType.labels[vulnerabilityType]! : detail,
      lat: lat,
      lng: lng,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
      isPending: true,
    );
    await _save(report);
    return report;
  }

  @override
  Future<VulnerableReport> offerHelp({
    required String tenantId,
    required String reportId,
    required String helperUserId,
  }) async {
    final db = await _db.database;
    final rows = await db.query(
      VulnerableReportModel.table,
      where: 'id = ? AND tenant_id = ? AND is_deleted = 0',
      whereArgs: [reportId, tenantId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw ArgumentError.value(reportId, 'reportId', 'Reporte no encontrado');
    }
    final current = VulnerableReportModel.fromSqlite(rows.first);
    if (current.reporterUserId == helperUserId) {
      throw ArgumentError.value(helperUserId, 'helperUserId', 'No puedes ofrecer ayuda en tu propio pedido');
    }
    final updated = current.copyWith(
      status: ReportStatus.vecinosEnCamino,
      helperUserId: helperUserId,
      isPending: true,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );
    await _save(updated);
    return updated;
  }

  Future<void> _save(VulnerableReport report) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.rawInsert(
        'INSERT OR REPLACE INTO ${VulnerableReportModel.table} '
        '(id, tenant_id, reporter_user_id, urgency_level, vulnerability_type, description, '
        'lat, lng, status, helper_user_id, is_deleted, updated_at, sync_status) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        VulnerableReportModel.toSqlite(report, syncStatus: SqliteTables.syncPending).values.toList(),
      );
      await _outboxDao.queueMutation(
        tenantId: report.tenantId,
        targetTable: VulnerableReportModel.table,
        recordId: report.id,
        operation: OutboxOperation.upsert,
        payload: VulnerableReportModel.toSyncPayload(report),
        executor: txn,
      );
    });
    _localChanges.add(null);
  }
}
