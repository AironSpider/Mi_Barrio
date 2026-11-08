import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/barrio_context/tenant_session.dart';
import '../../../../core/database_sqlite/sync_outbox_dao.dart';
import '../../../../core/sync_manager/sync_coordinator.dart';
import '../../../../core/ui_kit/app_theme.dart';
import '../../../../shared/local_distance.dart';
import '../../../proximity_services/data/datasources/services_sqlite_ds.dart';
import '../../../proximity_services/data/models/service_model.dart';
import '../../../proximity_services/presentation/widgets/service_detail_sheet.dart';
import '../../../solidarity_network/data/datasources/solidarity_sqlite_ds.dart';
import '../../../solidarity_network/data/models/solidarity_post_model.dart';
import '../../../solidarity_network/presentation/screens/favor_detail_screen.dart';
import '../providers/emergency_provider.dart';

/// Lista del Mapa: los mismos favores y servicios que se ven en el mapa
/// (antes la lista solo mostraba pedidos de ayuda y casi siempre salía vacía).
/// Funciona sin internet: lee el teléfono.
class NearbyPostsList extends StatefulWidget {
  const NearbyPostsList({
    super.key,
    this.location,
    this.servicesDatasource,
    this.solidarityDatasource,
  });

  final HelpLocation? location;
  final ServicesSqliteDatasource? servicesDatasource;
  final SolidaritySqliteDatasource? solidarityDatasource;

  static const listKey = ValueKey('nearby_posts_list');

  @override
  State<NearbyPostsList> createState() => _NearbyPostsListState();
}

class _Entry {
  const _Entry({this.post, this.service, required this.km, required this.emergency});

  final SolidarityPostModel? post;
  final LocalServiceModel? service;
  final double km;
  final bool emergency;
}

class _NearbyPostsListState extends State<NearbyPostsList> {
  late final ServicesSqliteDatasource _services =
      widget.servicesDatasource ?? ServicesSqliteDatasource();
  late final SolidaritySqliteDatasource _wall =
      widget.solidarityDatasource ?? SolidaritySqliteDatasource();
  StreamSubscription<String>? _queueSub;
  List<_Entry> _entries = const [];
  bool _loading = true;
  int _version = 0;

  @override
  void initState() {
    super.initState();
    _queueSub = SyncOutboxDao.onQueued.listen((_) => _load());
    SyncCoordinator.instance.lastSuccess.addListener(_load);
    _load();
  }

  @override
  void didUpdateWidget(covariant NearbyPostsList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location != widget.location) _load();
  }

  @override
  void dispose() {
    unawaited(_queueSub?.cancel());
    SyncCoordinator.instance.lastSuccess.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final version = ++_version;
    final session = TenantSession.instance;
    final lat = widget.location?.lat ?? session.centerLat;
    final lng = widget.location?.lng ?? session.centerLng;
    final entries = <_Entry>[];
    try {
      for (final p in await _wall.getActivePosts(session.tenantId, includeCompleted: false)) {
        entries.add(_Entry(
          post: p,
          km: LocalDistance.km(lat, lng, p.lat, p.lng),
          emergency: p.isEmergencyContext,
        ));
      }
      for (final s in await _services.getServices(session.tenantId)) {
        entries.add(_Entry(
          service: s,
          km: LocalDistance.km(lat, lng, s.lat, s.lng),
          emergency: s.isAvailableInEmergency,
        ));
      }
    } catch (_) {/* sin base local (tests): lista vacía */}
    entries.sort((a, b) => a.km.compareTo(b.km));
    if (!mounted || version != _version) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  Future<void> _open(_Entry e) async {
    final session = TenantSession.instance;
    final post = e.post;
    if (post != null) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => FavorDetailScreen(
            post: post,
            onCoordinate: (p) async {
              await _wall.coordinatePost(
                tenantId: session.tenantId,
                postId: p.id,
                coordinatorUserId: session.userId,
              );
            },
            onChangeStatus: (p, status) => _wall.changeMyPostStatus(
              tenantId: session.tenantId,
              postId: p.id,
              authorUserId: session.userId,
              newStatus: status,
            ),
          ),
        ),
      );
    } else if (e.service != null) {
      await showServiceDetailSheet(
        context,
        service: e.service!,
        tenantId: session.tenantId,
        userId: session.userId,
      );
    }
    if (mounted) unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    return Column(
      key: NearbyPostsList.listKey,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Text('Favores y servicios cerca', style: texto.titleMedium),
        const SizedBox(height: 8),
        if (_loading)
          Text('Cargando…', style: texto.bodyMedium)
        else if (_entries.isEmpty)
          Text(
            'Todavía no hay favores ni servicios publicados en tu barrio.',
            style: texto.bodyMedium,
          )
        else
          for (final e in _entries) _EntryTile(entry: e, onTap: () => _open(e)),
      ],
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, required this.onTap});

  final _Entry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colores = MiBarrioColors.of(context);
    final me = TenantSession.instance.userId;
    final post = entry.post;
    final service = entry.service;
    final isService = service != null;
    final isOwn = isService ? service.providerUserId == me : post!.authorUserId == me;
    final isNeed = isService
        ? service.isNeed
        : post!.flowType == SolidarityFlowType.solicitoAyuda;
    final kind = isService
        ? (ServiceCategory.labels[service.category] ?? 'Servicio')
        : (SolidarityModality.labels[post!.modality] ?? 'Favor');
    final subtitle = [
      isService ? 'Servicio' : 'Favor',
      isNeed ? 'Pide' : 'Brinda',
      kind,
      'a ${LocalDistance.label(entry.km)}',
      if (entry.emergency) 'Emergencia',
    ].join(' · ');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: isOwn ? colores.accentSoft : null,
      child: ListTile(
        key: ValueKey('nearby_${isService ? service.id : post!.id}'),
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: isOwn ? Colors.white : colores.accentSoft,
          foregroundColor: isService ? AppPalette.daySecondary : colores.brand,
          child: Icon(
            isService ? Icons.handyman_rounded : Icons.volunteer_activism_rounded,
          ),
        ),
        title: Text(
          isService ? service.title : post!.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(isOwn ? 'Tuyo · $subtitle' : subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}
