import '../../../core/barrio_context/tenant_session.dart';
import '../../../core/database_sqlite/local_id.dart';
import '../../../core/database_sqlite/sqlite_database.dart';
import '../../../core/database_sqlite/sqlite_tables.dart';
import '../../../core/database_sqlite/sync_outbox_dao.dart';
import '../../../core/network/api_client.dart';

/// Qué se reporta (contrato: `target_type`).
class ReportTarget {
  ReportTarget._();
  static const post = 'SOLIDARITY_POST';
  static const service = 'LOCAL_SERVICE';
}

/// Motivos del reporte (contrato: `reason`), en el orden en que se muestran.
class ReportReason {
  ReportReason._();
  static const falso = 'FALSO';
  static const estafa = 'ESTAFA';
  static const ofensivo = 'OFENSIVO';
  static const spam = 'SPAM';
  static const peligroso = 'PELIGROSO';
  static const datosPersonales = 'DATOS_PERSONALES';
  static const otro = 'OTRO';

  static const labels = {
    falso: 'Es falso o engañoso',
    estafa: 'Parece una estafa o pide dinero por adelantado',
    ofensivo: 'Es ofensivo o es acoso',
    spam: 'Está repetido o es spam',
    peligroso: 'Es peligroso o ilegal',
    datosPersonales: 'Muestra datos personales de otra persona',
    otro: 'Otro',
  };
}

/// Reportes del vecino: se guardan en el teléfono y se suben por el sync,
/// así funcionan sin internet. Lo reportado deja de verse para quien reporta.
class ContentReportsDatasource {
  ContentReportsDatasource({LocalDatabase? database, SyncOutboxDao? outboxDao})
    : _db = database ?? LocalDatabase.instance,
      _outboxDao = outboxDao ?? SyncOutboxDao();

  final LocalDatabase _db;
  final SyncOutboxDao _outboxDao;

  static const table = 'content_reports';
  static const maxDetail = 300;

  Future<bool> hasReported(String targetId, {String? userId}) async {
    final db = await _db.database;
    final rows = await db.query(
      table,
      columns: ['id'],
      where: 'target_id = ? AND reporter_user_id = ?',
      whereArgs: [targetId, userId ?? TenantSession.instance.userId],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  /// Guarda el reporte (PENDING) y lo encola. Lanza [ArgumentError] si falta
  /// el motivo escrito de "Otro".
  Future<void> report({
    required String targetType,
    required String targetId,
    required String reason,
    String? detail,
    String? tenantId,
    String? userId,
  }) async {
    if (!ReportReason.labels.containsKey(reason)) {
      throw ArgumentError.value(reason, 'reason', 'Motivo inválido');
    }
    final cleanDetail = detail?.trim();
    if (reason == ReportReason.otro && (cleanDetail == null || cleanDetail.length < 3)) {
      throw ArgumentError.value(detail, 'detail', 'Cuéntanos el motivo');
    }
    final tenant = tenantId ?? TenantSession.instance.tenantId;
    final reporter = userId ?? TenantSession.instance.userId;
    final row = {
      'id': LocalId.generate(),
      'tenant_id': tenant,
      'reporter_user_id': reporter,
      'target_type': targetType,
      'target_id': targetId,
      'reason': reason,
      'detail': (cleanDetail == null || cleanDetail.isEmpty)
          ? null
          : cleanDetail.substring(0, cleanDetail.length.clamp(0, maxDetail)),
      'is_deleted': 0,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      'sync_status': SqliteTables.syncPending,
    };
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.insert(table, row);
      await _outboxDao.queueMutation(
        tenantId: tenant,
        targetTable: table,
        recordId: row['id']! as String,
        operation: OutboxOperation.upsert,
        payload: {
          'id': row['id'],
          'reporter_user_id': reporter,
          'target_type': targetType,
          'target_id': targetId,
          'reason': reason,
          'detail': row['detail'],
          'is_deleted': false,
          'updated_at': row['updated_at'],
        },
        executor: txn,
      );
    });
  }
}

/// Publicación reportada, tal como la ve el administrador.
class ReportedItem {
  const ReportedItem({
    required this.targetType,
    required this.targetId,
    required this.tenantId,
    required this.title,
    required this.isUnderReview,
    required this.reportCount,
    required this.reasons,
    this.description,
    this.tenantName,
  });

  factory ReportedItem.fromJson(Map<String, dynamic> json) => ReportedItem(
    targetType: json['target_type'] as String,
    targetId: json['target_id'] as String,
    tenantId: json['tenant_id'] as String,
    tenantName: json['tenant_name'] as String?,
    title: json['title'] as String? ?? '',
    description: json['description'] as String?,
    isUnderReview: json['is_under_review'] == true,
    reportCount: (json['report_count'] as num?)?.toInt() ?? 0,
    reasons: [
      for (final r in (json['reports'] as List? ?? const []))
        if (r is Map)
          [
            ReportReason.labels[r['reason']] ?? '${r['reason']}',
            if ((r['detail'] as String?)?.trim().isNotEmpty ?? false)
              '"${(r['detail'] as String).trim()}"',
          ].join(': '),
    ],
  );

  final String targetType;
  final String targetId;
  final String tenantId;
  final String? tenantName;
  final String title;
  final String? description;
  final bool isUnderReview;
  final int reportCount;
  final List<String> reasons;

  bool get isService => targetType == ReportTarget.service;
}

/// Panel de reportes: administrador del barrio ([tenantId]) o
/// superadministrador (sin barrio: ve todos).
class ModerationRemoteDatasource {
  ModerationRemoteDatasource({ApiClient? client, this.tenantId})
    : _api = client ?? ApiClient();

  final ApiClient _api;

  /// null = superadministrador (todos los barrios).
  final String? tenantId;

  bool get _isPlatform => tenantId == null;
  String get _base => _isPlatform ? '/api/v1/platform/reports' : '/api/v1/moderation/reports';

  Future<List<ReportedItem>> list() async {
    final r = await _api.get(_base, tenantId ?? '');
    final body = ApiClient.decodeOrThrow(r);
    return [
      for (final item in (body as List? ?? const []))
        if (item is Map<String, dynamic>) ReportedItem.fromJson(item),
    ];
  }

  Future<int> pendingCount() async {
    final r = await _api.get('$_base/count', tenantId ?? '');
    final body = ApiClient.decodeOrThrow(r);
    return body is Map ? (body['pending'] as num?)?.toInt() ?? 0 : 0;
  }

  /// [action]: `restore` (vuelve a mostrarse) o `remove` (se elimina).
  Future<void> resolve(ReportedItem item, String action) async {
    final r = await _api.post(
      '$_base/${item.targetType}/${item.targetId}/$action',
      tenantId ?? item.tenantId,
      const <String, Object?>{},
    );
    ApiClient.decodeOrThrow(r);
  }
}
