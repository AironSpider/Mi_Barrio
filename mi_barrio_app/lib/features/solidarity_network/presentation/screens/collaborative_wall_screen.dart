import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/barrio_context/tenant_session.dart';
import '../../../../core/database_sqlite/sync_outbox_dao.dart';
import '../../../../core/sync_manager/sync_coordinator.dart';
import '../../../../core/ui_kit/sync_status_chip.dart';
import '../../data/datasources/solidarity_sqlite_ds.dart';
import '../../data/models/solidarity_post_model.dart';

import '../../../../core/barrio_context/emergency_mode_provider.dart';
import '../../../../core/ui_kit/priority_podium_frame.dart';
import '../../../../shared/emergency_ranking.dart';

class CollaborativeWallScreen extends StatefulWidget {
  const CollaborativeWallScreen({
    super.key,
    this.criticalResourcesOnly = false,
    this.tenantId,
    this.datasource,
  });

  /// En Modo Emergencia prioriza recursos críticos (agua, botiquín, generador).
  final bool criticalResourcesOnly;
  final String? tenantId;
  final SolidaritySqliteDatasource? datasource;

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
    _sync.lastError.addListener(_onLastSyncErrorChanged);
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
    _sync.lastError.removeListener(_onLastSyncErrorChanged);
    unawaited(_queueSubscription.cancel());
    super.dispose();
  }

  void _onSyncPhaseChanged() {
    if (mounted) setState(() {});
    if (_sync.phase.value == SyncPhase.idle ||
        _sync.phase.value == SyncPhase.error) {
      _loadPosts();
    }
  }

  void _onLastSyncErrorChanged() {
    if (mounted) setState(() {});
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
      .where((post) => _flowFilter == null || post.flowType == _flowFilter)
      .toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final syncError = _sync.lastError.value;
    final hasSyncError =
        _sync.phase.value == SyncPhase.error &&
        syncError != null &&
        syncError.isNotEmpty;

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
          _buildSyncControls(context, hasSyncError, syncError),
          const SizedBox(height: 12),
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
            _buildPostList(),
        ],
      ),
    );
  }

  
  Widget _buildPostList() {
    return ValueListenableBuilder<bool>(
      valueListenable: EmergencyModeProvider.instance.isActive,
      builder: (context, emergency, _) {
        final session = TenantSession.instance;
        final ranked = emergency
            ? EmergencyRanking.rankPosts(
                _visiblePosts,
                lat: session.centerLat,
                lng: session.centerLng,
              )
            : null;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          child: Column(
            key: ValueKey(
              ranked == null
                  ? 'normal'
                  : 'podio_${ranked.map((r) => r.item.id).join(',')}',
            ),
            children: ranked == null
                ? [for (final post in _visiblePosts) _PostCard(post: post)]
                : [
                    for (final r in ranked)
                      PriorityPodiumFrame(
                        priority: r.priority,
                        child: _PostCard(post: r.item),
                      ),
                  ],
          ),
        );
      },
    );
  }

  Widget _buildSyncControls(
    BuildContext context,
    bool hasSyncError,
    String? syncError,
  ) {
    final phase = _sync.phase.value;
    final syncing = phase == SyncPhase.syncing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                phase == SyncPhase.offline
                    ? 'Sin conexión: puedes publicar y se enviará al volver internet.'
                    : syncing
                    ? 'Actualizando publicaciones del barrio…'
                    : 'Las publicaciones se actualizan automáticamente.',
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
        ),
        if (hasSyncError)
          _buildMessage(
            context,
            icon: Icons.cloud_off_rounded,
            message:
                'No se pudo sincronizar. La publicación sigue guardada en este teléfono y se reintentará. $syncError',
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
  const _PostCard({required this.post});

  final SolidarityPostModel post;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isOffer = post.flowType == SolidarityFlowType.ofrezcoAyuda;
    return Card(
      key: ValueKey('solidarity_post_${post.id}'),
      margin: const EdgeInsets.only(bottom: 10),
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
                SyncStatusChip.fromPending(post.isPending),
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
            if (post.description != null) ...[
              const SizedBox(height: 8),
              Text(post.description!),
            ],
          ],
        ),
      ),
    );
  }
}
