import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/barrio_context/emergency_mode_provider.dart';
import '../../../../core/ui_kit/publish_action.dart';
import '../../../../core/barrio_context/tenant_session.dart';
import '../../../../core/database_sqlite/sync_outbox_dao.dart';
import '../../../../core/sync_manager/sync_coordinator.dart';
import '../../../../core/ui_kit/app_theme.dart';
import '../../../../core/ui_kit/podium_frame.dart';
import '../../../../core/ui_kit/search_filter_bar.dart';
import '../../../../core/ui_kit/sync_status_chip.dart';
import '../../../../shared/emergency_ranking.dart';
import '../../../../shared/local_distance.dart';
import '../../data/datasources/solidarity_sqlite_ds.dart';
import '../../data/models/solidarity_post_model.dart';
import '../widgets/post_meta_label.dart';
import '../widgets/support_groups_section.dart';
import 'favor_detail_screen.dart';

/// Muro de favores del barrio (pido / ofrezco ayuda), con búsqueda y filtros.
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
  String _searchQuery = '';
  late FilterSelection _filters = _withEmergencyDefault(const {});

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
    if (mounted) setState(() => _filters = _withEmergencyDefault(_filters));
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
        debugPrint('No se pudieron cargar las publicaciones: $error');
        _isLoading = false;
      });
    }
  }

  /// Grupos del modal de filtros (los valores son los mismos del servidor).
  List<FilterGroup> get _filterGroups => [
    const FilterGroup(
      id: _flowGroup,
      title: 'Modalidad',
      allLabel: 'Todas',
      options: [
        FilterOption(SolidarityFlowType.solicitoAyuda, 'Pedir'),
        FilterOption(SolidarityFlowType.ofrezcoAyuda, 'Brindar'),
      ],
    ),
    const FilterGroup.toggle(id: _mineGroup, title: 'Seleccionar los míos'),
    const FilterGroup.toggle(
      id: _emergencyGroup,
      title: 'Seleccionar apoyo de emergencia',
    ),
    FilterGroup(
      id: _typeGroup,
      title: 'Tipo',
      multiple: true,
      options: [
        for (final entry in SolidarityModality.labels.entries)
          // "Recurso crítico" solo existe en emergencia.
          if (entry.key != SolidarityModality.recursoCritico ||
              EmergencyModeProvider.instance.isActive.value)
            FilterOption(entry.key, entry.value),
      ],
    ),
    DistanceFilter.group,
  ];

  static const _flowGroup = 'modalidad';
  static const _typeGroup = 'tipo';
  static const _mineGroup = 'mios';
  static const _emergencyGroup = 'emergencia';

  /// En modo emergencia el filtro "de emergencia" viene encendido (el vecino
  /// puede apagarlo); al salir del modo se apaga.
  FilterSelection _withEmergencyDefault(FilterSelection current) => {
    ...current,
    _emergencyGroup: {
      if (EmergencyModeProvider.instance.isActive.value) FilterGroup.on,
    },
  };

  bool get _hasFilters =>
      _searchQuery.trim().isNotEmpty || activeFilterCount(_filters) > 0;

  List<SolidarityPostModel> get _visiblePosts {
    final query = _searchQuery.trim().toLowerCase();
    final flows = _filters[_flowGroup];
    final types = _filters[_typeGroup];
    final distance = _filters[DistanceFilter.groupId];
    final mine = isToggleOn(_filters, _mineGroup);
    final emergencyOnly = isToggleOn(_filters, _emergencyGroup);
    final session = TenantSession.instance;
    return _posts
        .where((post) {
          if (mine && post.authorUserId != session.userId) return false;
          if (emergencyOnly && !post.isEmergencyContext) return false;
          if (flows != null &&
              flows.isNotEmpty &&
              !flows.contains(post.flowType)) {
            return false;
          }
          if (types != null &&
              types.isNotEmpty &&
              !types.contains(post.modality)) {
            return false;
          }
          if (distance != null && distance.isNotEmpty) {
            final km = LocalDistance.km(
              session.centerLat,
              session.centerLng,
              post.lat,
              post.lng,
            );
            if (!DistanceFilter.matches(distance, km)) return false;
          }
          if (query.isNotEmpty &&
              !post.title.toLowerCase().contains(query) &&
              !(post.description?.toLowerCase().contains(query) ?? false)) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
  }

  /// Detalle en pantalla completa (foto, contacto, chat, comentarios, reseñas).
  Future<void> _openDetail(SolidarityPostModel post) async {
    // Que al volver no se abra el teclado del buscador.
    FocusManager.instance.primaryFocus?.unfocus();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FavorDetailScreen(
          post: post,
          onCoordinate: widget.onCoordinate ?? _coordinate,
          onChangeStatus: (p, status) => _datasource.changeMyPostStatus(
            tenantId: _tenantId,
            postId: p.id,
            authorUserId: TenantSession.instance.userId,
            newStatus: status,
          ),
        ),
      ),
    );
    if (mounted) unawaited(_loadPosts());
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
      onRefresh: () async {
        await _sync.syncNow();
        await _loadPosts();
      },
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
          // Descripción + botón actualizar en una sola fila.
          _buildSyncControls(context),
          const SizedBox(height: 12),
          // En emergencia: grupos de apoyo del barrio antes del muro (Sprint 11).
          if (EmergencyModeProvider.instance.isActive.value) ...[
            const SupportGroupsSection(),
            const SizedBox(height: 16),
          ],
          SearchFilterBar(
            searchFieldKey: const ValueKey('wall_search'),
            filterButtonKey: const ValueKey('wall_filters_button'),
            hintText: 'Buscar en el muro',
            onSearchChanged: (value) => setState(() => _searchQuery = value),
            groups: _filterGroups,
            selection: _filters,
            onFiltersChanged: (value) => setState(() => _filters = value),
          ),
          const SizedBox(height: 12),
          // Si falla la lectura pero ya había publicaciones, se siguen mostrando.
          if (_loadError != null && _posts.isEmpty)
            _buildMessage(
              context,
              icon: Icons.error_outline_rounded,
              message:
                  'No pudimos mostrar las publicaciones. Toca "Reintentar"; si '
                  'sigue igual, cierra y abre la app.',
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
              message: _hasFilters
                  ? 'No hay publicaciones con esa búsqueda o esos filtros.'
                  : 'Todavía no hay publicaciones. Sé el primero en compartir algo con tu barrio.',
              action:
                  _hasFilters ||
                      EmergencyModeProvider.instance.isActive.value ||
                      PublishAction.maybeOf(context) == null
                  ? null
                  : FilledButton.tonalIcon(
                      onPressed: PublishAction.maybeOf(context),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Publicar algo'),
                    ),
            )
          else
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: Column(
                key: ValueKey(
                  'wall_list_${EmergencyModeProvider.instance.isActive.value}',
                ),
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
            'Préstamos, donaciones e intercambio de ayuda entre vecinos.',
            style: Theme.of(context).textTheme.bodyMedium,
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

  /// "hace 2 h · a 300 m" desde el punto de referencia del vecino.
  String? _metaLabel() {
    final session = TenantSession.instance;
    final km = LocalDistance.km(
      session.centerLat,
      session.centerLng,
      post.lat,
      post.lng,
    );
    return PostMetaLabel.build(updatedAtIso: post.updatedAt, distanceKm: km);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final colores = MiBarrioColors.of(context);
    final isOffer = post.flowType == SolidarityFlowType.ofrezcoAyuda;
    // Lo propio: fondo verde agua + etiqueta "Tuyo" (no solo color);
    // al tocarlo, gris suave.
    final isOwn = post.authorUserId == TenantSession.instance.userId;
    return Card(
      key: ValueKey('solidarity_post_${post.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      color: isOwn ? colores.accentSoft : null,
      child: InkWell(
        highlightColor: isOwn ? AppPalette.filterActiveBackground : null,
        splashColor: isOwn ? AppPalette.filterActiveBackground : null,
        onTap: onTap,
        // Para el lector de pantalla, la tarjeta es UN botón que lee todo
        // junto ("Pido ayuda, Préstamo de escalera, hace 2 h…").
        excludeFromSemantics: true,
        child: MergeSemantics(
          child: Semantics(
            button: true,
            onTap: onTap,
            hint: 'Toca dos veces para ver el detalle',
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
                        // Ícono con fondo blanco en las tarjetas propias.
                        backgroundColor: isOwn ? Colors.white : null,
                        avatar: Icon(
                          isOffer
                              ? Icons.favorite_rounded
                              : Icons.back_hand_rounded,
                          size: 18,
                          color: colorScheme.primary,
                        ),
                        label: Text(isOffer ? 'Brindo ayuda' : 'Pido ayuda'),
                      ),
                      if (isOwn)
                        Chip(
                          key: ValueKey('own_post_${post.id}'),
                          backgroundColor: Colors.white,
                          label: Text(
                            'Tuyo',
                            style: TextStyle(
                              color: colores.accentText,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      if (isOwn && post.isUnderReview)
                        Chip(
                          backgroundColor: AppPalette.failedBackground,
                          label: Text(
                            'En revisión',
                            style: TextStyle(color: colores.urgencyCritical),
                          ),
                        ),
                      if (post.isEmergencyContext)
                        const Chip(
                          avatar: Icon(Icons.emergency_rounded, size: 18),
                          label: Text('Emergencia'),
                        ),
                      if (post.hasPhoto)
                        const Chip(
                          avatar: Icon(Icons.photo_camera_rounded, size: 18),
                          label: Text('Con foto'),
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
                    [
                      SolidarityModality.labels[post.modality] ?? post.modality,
                      if (post.authorUserId == TenantSession.instance.userId)
                        'publicado por ti'
                      else if (post.authorName != null)
                        'por ${post.authorName}',
                    ].join(' · '),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  if (_metaLabel() case final meta?) ...[
                    const SizedBox(height: 4),
                    Row(
                      key: ValueKey('favor_meta_${post.id}'),
                      children: [
                        Icon(
                          Icons.schedule_rounded,
                          size: 18,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            meta,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                  ],
                  // Antes no se veía si alguien ya estaba ayudando.
                  if (post.status == SolidarityStatus.enCoordinacion) ...[
                    const SizedBox(height: 6),
                    Row(
                      key: ValueKey('favor_coordinating_${post.id}'),
                      children: [
                        Icon(
                          Icons.handshake_rounded,
                          size: 20,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            post.coordinatorName != null
                                ? '${post.coordinatorName} ya está ayudando'
                                : 'Alguien ya está ayudando',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (post.description != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      post.description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'Ver detalle, comentarios y contacto ›',
                      style: Theme.of(context).textTheme.labelLarge
                          ?.copyWith(color: colorScheme.primary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
