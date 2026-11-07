import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/barrio_context/tenant_session.dart';
import '../../../../core/database_sqlite/history_dao.dart';
import '../../../../core/database_sqlite/sqlite_tables.dart';
import '../../../../core/ui_kit/sync_status_chip.dart';
import '../../../emergency_support/domain/entities/vulnerable_report_entity.dart';
import '../../../proximity_services/data/models/service_model.dart';
import '../../../solidarity_network/data/models/solidarity_post_model.dart';

/// "Mi historial": lo que publicó el vecino, en 3 pestañas con contador.
/// Se lee solo del teléfono (funciona sin internet); cada ítem lleva su chip de sync.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, this.dao, this.tenantId, this.userId});

  final HistoryDao? dao;
  final String? tenantId;
  final String? userId;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late final HistoryDao _dao = widget.dao ?? HistoryDao();
  late final String _tenantId = widget.tenantId ?? TenantSession.instance.tenantId;
  late final String _userId = widget.userId ?? TenantSession.instance.userId;

  List<LocalServiceModel> _services = const [];
  List<SolidarityPostModel> _posts = const [];
  List<VulnerableReport> _sos = const [];
  bool _loading = true;
  bool _failed = false;

  static const _postStatus = {
    SolidarityStatus.disponible: 'Disponible',
    SolidarityStatus.enCoordinacion: 'En coordinación',
    SolidarityStatus.completado: 'Completado',
  };

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final results = await Future.wait([
        _dao.myServices(_tenantId, _userId),
        _dao.myPosts(_tenantId, _userId),
        _dao.mySos(_tenantId, _userId),
      ]);
      if (!mounted) return;
      setState(() {
        _services = results[0] as List<LocalServiceModel>;
        _posts = results[1] as List<SolidarityPostModel>;
        _sos = results[2] as List<VulnerableReport>;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _failed = true;
          _loading = false;
        });
      }
    }
  }

  static SyncChipStatus _chip(String syncStatus) => switch (syncStatus) {
        SqliteTables.syncPending => SyncChipStatus.pending,
        SqliteTables.syncFailed => SyncChipStatus.failed,
        _ => SyncChipStatus.synced,
      };

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Mi historial'),
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: 'Mis servicios (${_services.length})'),
              Tab(text: 'Mis favores (${_posts.length})'),
              Tab(text: 'Mis SOS (${_sos.length})'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _failed
                ? _Message(
                    icon: Icons.error_outline_rounded,
                    text: 'No pudimos abrir tu historial.',
                    action: TextButton(onPressed: _load, child: const Text('Reintentar')),
                  )
                : TabBarView(
                    children: [
                      _list(
                        empty: 'Aún no ofreces servicios.',
                        children: [
                          for (final s in _services)
                            _HistoryTile(
                              icon: Icons.handyman_rounded,
                              title: s.title,
                              subtitle: ServiceCategory.labels[s.category] ?? s.category,
                              chip: _chip(s.syncStatus),
                            ),
                        ],
                      ),
                      _list(
                        empty: 'Aún no publicaste favores.',
                        children: [
                          for (final p in _posts)
                            _HistoryTile(
                              icon: p.flowType == SolidarityFlowType.ofrezcoAyuda
                                  ? Icons.favorite_rounded
                                  : Icons.back_hand_rounded,
                              title: p.title,
                              subtitle: _postStatus[p.status] ?? p.status,
                              chip: _chip(p.syncStatus),
                            ),
                        ],
                      ),
                      _list(
                        empty: 'Aún no creaste alertas.',
                        children: [
                          for (final r in _sos)
                            _HistoryTile(
                              icon: Icons.sos_rounded,
                              title: VulnerabilityType.labels[r.vulnerabilityType] ?? r.vulnerabilityType,
                              subtitle: ReportStatus.labels[r.status] ?? r.status,
                              chip: r.isPending ? SyncChipStatus.pending : SyncChipStatus.synced,
                            ),
                        ],
                      ),
                    ],
                  ),
      ),
    );
  }

  Widget _list({required String empty, required List<Widget> children}) {
    if (children.isEmpty) return _Message(icon: Icons.inbox_outlined, text: empty);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: children),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.chip,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final SyncChipStatus chip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(subtitle, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 8),
                  SyncStatusChip(status: chip),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
            ?action,
          ],
        ),
      ),
    );
  }
}
