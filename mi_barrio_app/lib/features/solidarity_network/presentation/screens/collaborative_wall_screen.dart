import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/barrio_context/emergency_mode_provider.dart';
import '../../../../core/barrio_context/tenant_session.dart';
import '../../../../core/database_sqlite/sync_outbox_dao.dart';
import '../../../../core/sync_manager/sync_coordinator.dart';
import '../../../../core/ui_kit/podium_frame.dart';
import '../../../../core/ui_kit/sync_status_chip.dart';
import '../../../../shared/emergency_ranking.dart';
import '../../data/datasources/solidarity_sqlite_ds.dart';
import '../../data/models/solidarity_post_model.dart';
import '../widgets/favor_detail_sheet.dart';
import '../widgets/support_groups_section.dart';

class CollaborativeWallScreen extends StatefulWidget {
  const CollaborativeWallScreen({
    super.key,
    this.criticalResourcesOnly = false,
    this.tenantId,
    this.datasource,
    this.onCoordinate,
  });

  /// En Modo Emergencia prioriza recursos críticos (agua, botiquín, generador).
  final bool criticalResourcesOnly;
  final String? tenantId;
  final SolidaritySqliteDatasource? datasource;

  /// Marca un favor ajeno como "en coordinación" (método de la capa de datos).
  /// Si es null, el botón "Coordinar" del detalle aparece desactivado.
  final CoordinateFavorCallback? onCoordinate;

  @override
  State<CollaborativeWallScreen> createState() =>
      _CollaborativeWallScreenState();
}

class _CollaborativeWallScreenState extends State<CollaborativeWallScreen> {
  late final String _tenantId;
  late final SolidaritySqliteDatasource _datasource;
  late final SyncCoordinator _sync;
  late final StreamSubscription<String> _queueSubscription;

  List<SolidarityPostModel> _posts = const [];
  bool _isLoading = true;
  String? _loadError;
  int _loadVersion = 0;
  String? _flowFilter;

  @override
  void initState() {
    super.initState();
    _tenantId = widget.tenantId ?? TenantSession.instance.tenantId;
    _datasource = widget.datasource ?? SolidaritySqliteDatasource();
    _sync = SyncCoordinator.instance;
    _sync.phase.addListener(_onSyncPhaseChanged);
    EmergencyModeProvider.instance.isActive.addListener(_onEmergencyChanged);
    _queueSubscription = SyncOutboxDao.onQueued.listen((tenantId) {
      if (tenantId == _tenantId) _loadPosts();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_loadPosts());
    });
  }

  @override
  void dispose() {
    _sync.phase.removeListener(_onSyncPhaseChanged);
    EmergencyModeProvider.instance.isActive.removeListener(_onEmergencyChanged);
    unawaited(_queueSubscription.cancel());
    super.dispose();
  }

  void _onEmergencyChanged() {
    if (mounted) setState(() {});
  }

  void _onSyncPhaseChanged() {
    if (mounted) setState(() {});
    if (_sync.phase.value == SyncPhase.idle ||
        _sync.phase.value == SyncPhase.error) {
      _loadPosts();
    }
  }

  Future<void> _loadPosts() async {
    final version = ++_loadVersion;
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final posts = await _datasource.getActivePosts(
        _tenantId,
        emergencyOnly: widget.criticalResourcesOnly,
        includeCompleted: false,
      );
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _posts = posts;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _loadError = error.toString();
        _isLoading = false;
      });
    }
  }

  List<SolidarityPostModel> get _visiblePosts => _posts
      .where((post) => post.status != SolidarityStatus.completado)
      .where((post) => _flowFilter == null || post.flowType == _flowFilter)
      .toList(growable: false);

  void _openDetail(SolidarityPostModel post) {
    unawaited(
      showFavorDetailSheet(
        context,
        post: post,
        userId: TenantSession.instance.userId,
        onCoordinate: widget.onCoordinate ?? _coordinate,
      ),
    );
  }

  /// Coordina un favor ajeno: guarda PENDING en el teléfono y encola el cambio.
  Future<void> _coordinate(SolidarityPostModel post) async {
    await _datasource.coordinatePost(
      tenantId: _tenantId,
      postId: post.id,
      coordinatorUserId: TenantSession.instance.userId,
    );
    if (mounted) unawaited(_loadPosts());
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadPosts,
      child: ListView(
        key: const ValueKey('collaborative_wall_list'),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        children: [
          Text(
            widget.criticalResourcesOnly
                ? 'Recursos críticos'
                : 'Muro solidario',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          Text(
            'Préstamos, donaciones e intercambio de ayuda entre vecinos.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          _buildSyncControls(context),
          const SizedBox(height: 12),
          // En emergencia: grupos de apoyo del barrio antes del muro (Sprint 11).
          if (EmergencyModeProvider.instance.isActive.value) ...[
            const SupportGroupsSection(),
            const SizedBox(height: 16),
          ],
          Wrap(
            spacing: 8,
            children: [
              _flowChip('Todas', null),
              _flowChip('Necesito', SolidarityFlowType.solicitoAyuda),
              _flowChip('Ofrezco', SolidarityFlowType.ofrezcoAyuda),
            ],
          ),
          const SizedBox(height: 12),
          if (_loadError != null)
            _buildMessage(
              context,
              icon: Icons.error_outline_rounded,
              message: 'No se pudieron cargar las publicaciones: $_loadError',
              action: TextButton(
                onPressed: _loadPosts,
                child: const Text('Reintentar'),
              ),
            )
          else if (_isLoading && _posts.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: Text('Cargando publicaciones…')),
              ),
            )
          else if (_visiblePosts.isEmpty)
            _buildMessage(
              context,
              icon: Icons.forum_outlined,
              message: _flowFilter == null
                  ? 'Todavía no hay publicaciones. Sé el primero en compartir algo con tu barrio.'
                  : 'No hay publicaciones en esta categoría.',
            )
          else
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: Column(
                key: ValueKey('wall_list_${EmergencyModeProvider.instance.isActive.value}'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _buildPostList(),
              ),
            ),
        ],
      ),
    );
  }

  /// En emergencia, los 3 primeros según el ranking suben arriba con el
  /// marco "Prioridad 1/2/3"; el resto sigue en su orden normal.
  List<Widget> _buildPostList() {
    final posts = _visiblePosts;
    Widget card(SolidarityPostModel p) =>
        _PostCard(post: p, onTap: () => _openDetail(p));
    if (!EmergencyModeProvider.instance.isActive.value) {
      return [for (final p in posts) card(p)];
    }
    final session = TenantSession.instance;
    final ranked = EmergencyRanking.rankPosts(
      posts,
      lat: session.centerLat,
      lng: session.centerLng,
    );
    final podium = ranked.where((r) => r.isPodium).toList();
    final podiumIds = {for (final r in podium) r.item.id};
    return [
      for (final r in podium)
        PodiumFrame(
          key: ValueKey('podium_post_${r.item.id}'),
          priority: r.priority!,
          child: card(r.item),
        ),
      for (final p in posts)
        if (!podiumIds.contains(p.id)) card(p),
    ];
  }

  /// Solo el botón de actualizar: el estado de la sincronización (offline,
  /// reintentos, errores) ya lo muestra la barra global en todas las pestañas.
  Widget _buildSyncControls(BuildContext context) {
    final syncing = _sync.phase.value == SyncPhase.syncing;
    return Row(
      children: [
        Expanded(
          child: Text(
            'Las publicaciones se actualizan automáticamente.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        IconButton(
          tooltip: 'Actualizar muro',
          onPressed: syncing
              ? null
              : () {
                  unawaited(_sync.syncNow());
                  unawaited(_loadPosts());
                },
          icon: syncing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh_rounded),
        ),
      ],
    );
  }

  Widget _flowChip(String label, String? flowType) {
    return ChoiceChip(
      label: Text(label),
      selected: _flowFilter == flowType,
      onSelected: (_) => setState(() => _flowFilter = flowType),
    );
  }

  Widget _buildMessage(
    BuildContext context, {
    required IconData icon,
    required String message,
    Widget? action,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, size: 32),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            ?action,
          ],
        ),
      ),
    );
  }
}

class _PostCard extends StatelessWidget {
  const _PostCard({required this.post, required this.onTap});

  final SolidarityPostModel post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isOffer = post.flowType == SolidarityFlowType.ofrezcoAyuda;
    return Card(
      key: ValueKey('solidarity_post_${post.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Chip(
                  avatar: Icon(
                    isOffer ? Icons.favorite_rounded : Icons.back_hand_rounded,
                    size: 18,
                    color: colorScheme.primary,
                  ),
                  label: Text(isOffer ? 'Ofrezco ayuda' : 'Necesito ayuda'),
                ),
                if (post.isEmergencyContext)
                  const Chip(
                    avatar: Icon(Icons.emergency_rounded, size: 18),
                    label: Text('Emergencia'),
                  ),
                if (post.isPending) SyncStatusChip.fromPending(true),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              post.title,
              style: Theme.of(context).textTheme.titleLarge,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              SolidarityModality.labels[post.modality] ?? post.modality,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            // Antes no se veía si alguien ya estaba ayudando.
            if (post.status == SolidarityStatus.enCoordinacion) ...[
              const SizedBox(height: 6),
              Row(
                key: ValueKey('favor_coordinating_${post.id}'),
                children: [
                  Icon(Icons.handshake_rounded, size: 20, color: colorScheme.primary),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Alguien ya está ayudando',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                ],
              ),
            ],
            if (post.description != null) ...[
              const SizedBox(height: 8),
              Text(post.description!),
            ],
          ],
        ),
      ),
      ),
    );
  }
}
