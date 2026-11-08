import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/barrio_context/emergency_mode_provider.dart';
import '../../../../core/barrio_context/tenant_session.dart';
import '../../../../core/database_sqlite/sync_outbox_dao.dart';
import '../../../../core/sync_manager/sync_coordinator.dart';
import '../../../../core/ui_kit/done_confirmation.dart';
import '../../../../core/ui_kit/podium_frame.dart';
import '../../../../core/ui_kit/search_filter_bar.dart';
import '../../../../shared/emergency_ranking.dart';
import '../../../../shared/local_distance.dart';
import '../../data/datasources/endorsements_sqlite_ds.dart';
import '../../data/datasources/services_sqlite_ds.dart';
import '../../data/models/endorsement_model.dart';
import '../../data/models/service_model.dart';
import '../widgets/offer_service_sheet.dart';
import '../widgets/service_card.dart';
import '../widgets/service_detail_sheet.dart';
import '../widgets/service_category_ui.dart';

class ServicesDirectoryScreen extends StatefulWidget {
  const ServicesDirectoryScreen({
    super.key,
    this.emergencyOnly = false,
    this.tenantId,
    this.userId,
    this.servicesDatasource,
    this.endorsementsDatasource,
  });

  final bool emergencyOnly;
  final String? tenantId;
  final String? userId;
  final ServicesSqliteDatasource? servicesDatasource;
  final EndorsementsSqliteDatasource? endorsementsDatasource;

  @override
  State<ServicesDirectoryScreen> createState() =>
      _ServicesDirectoryScreenState();
}

class _ServicesDirectoryScreenState extends State<ServicesDirectoryScreen> {
  /// "Todos" + todos los rubros (fila deslizable).
  static final _categories = <String?>[null, ...ServiceCategory.labels.keys];

  late final String _tenantId;
  late final String _userId;
  late final ServicesSqliteDatasource _servicesDatasource;
  late final EndorsementsSqliteDatasource _endorsementsDatasource;
  late final SyncCoordinator _sync;
  late final StreamSubscription<String> _queueSubscription;

  String? _selectedCategory;
  String _searchQuery = '';
  FilterSelection _filters = const {};
  List<LocalServiceModel> _services = const [];
  final Map<String, EndorsementModel> _myEndorsements = {};
  final Set<String> _updatingEndorsements = {};
  bool _isLoading = true;
  String? _loadError;
  int _loadVersion = 0;
  MerchantProfile _merchant = const MerchantProfile.none();

  @override
  void initState() {
    super.initState();
    _tenantId = widget.tenantId ?? TenantSession.instance.tenantId;
    _userId = widget.userId ?? TenantSession.instance.userId;
    _servicesDatasource =
        widget.servicesDatasource ?? ServicesSqliteDatasource();
    _endorsementsDatasource =
        widget.endorsementsDatasource ?? EndorsementsSqliteDatasource();
    _sync = SyncCoordinator.instance;
    _sync.phase.addListener(_onSyncChanged);
    EmergencyModeProvider.instance.isActive.addListener(_onEmergencyChanged);
    _queueSubscription = SyncOutboxDao.onQueued.listen((tenantId) {
      if (tenantId == _tenantId) _loadServices();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_loadServices());
      unawaited(_loadMerchant());
    });
  }

  @override
  void didUpdateWidget(covariant ServicesDirectoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.emergencyOnly != widget.emergencyOnly) {
      unawaited(_loadServices());
    }
  }

  @override
  void dispose() {
    _sync.phase.removeListener(_onSyncChanged);
    EmergencyModeProvider.instance.isActive.removeListener(_onEmergencyChanged);
    unawaited(_queueSubscription.cancel());
    super.dispose();
  }

  void _onEmergencyChanged() {
    if (mounted) setState(() {});
  }

  void _onSyncChanged() {
    if (_sync.phase.value == SyncPhase.idle ||
        _sync.phase.value == SyncPhase.error) {
      _loadServices();
    }
  }

  Future<void> _loadServices() async {
    final version = ++_loadVersion;
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final services = await _servicesDatasource.getServices(
        _tenantId,
        category: _selectedCategory,
        emergencyOnly: widget.emergencyOnly,
      );
      final endorsements = await Future.wait(
        services.map(
          (service) => _endorsementsDatasource.myRating(service.id, _userId),
        ),
      );
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _services = services;
        _myEndorsements
          ..clear()
          ..addEntries([
            for (var i = 0; i < services.length; i++)
              if (endorsements[i] != null)
                MapEntry(services[i].id, endorsements[i]!),
          ]);
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

  Future<void> _toggleEndorsement(LocalServiceModel service) async {
    if (_updatingEndorsements.contains(service.id) ||
        service.providerUserId == _userId) {
      return;
    }
    setState(() => _updatingEndorsements.add(service.id));
    try {
      final current = _myEndorsements[service.id];
      if (current == null) {
        await _endorsementsDatasource.rateService(
          tenantId: _tenantId,
          serviceId: service.id,
          endorserUserId: _userId,
        );
      } else {
        await _endorsementsDatasource.removeEndorsement(
          tenantId: _tenantId,
          serviceId: service.id,
          endorserUserId: _userId,
        );
      }
      await _loadServices();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              current == null
                  ? 'Visto bueno guardado; se sincronizará en segundo plano.'
                  : 'Visto bueno retirado; se sincronizará en segundo plano.',
            ),
          ),
        );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('No se pudo guardar el visto bueno: $error')),
        );
    } finally {
      if (mounted) setState(() => _updatingEndorsements.remove(service.id));
    }
  }

  Future<void> _loadMerchant() async {
    final profile = await loadMerchantProfile(_userId, tenantId: _tenantId);
    if (!mounted) return;
    setState(() => _merchant = profile);
  }

  Future<void> _openOffer() async {
    final messenger = ScaffoldMessenger.of(context);
    final published = await showOfferServiceSheet(
      context,
      tenantId: _tenantId,
      userId: _userId,
      datasource: _servicesDatasource,
      profile: _merchant,
    );
    if (!published || !mounted) return;
    DoneConfirmation.show(
      messenger,
      'Tu servicio ya está publicado. Se enviará solo cuando haya señal.',
    );
  }

  static const _categoryGroup = 'oficio';

  /// Grupos del modal de filtros: Oficio (uno) y Distancia.
  List<FilterGroup> get _filterGroups => [
        FilterGroup(
          id: _categoryGroup,
          title: 'Oficio',
          allLabel: 'Todos',
          options: [
            for (final category in _categories)
              if (category != null)
                FilterOption(category, ServiceCategoryUi.shortLabel(category)),
          ],
        ),
        DistanceFilter.group,
      ];

  /// El oficio se filtra en la base local (como antes); la distancia y la
  /// búsqueda, en memoria.
  void _applyFilters(FilterSelection value) {
    final category = value[_categoryGroup];
    final newCategory =
        category == null || category.isEmpty ? null : category.first;
    final categoryChanged = newCategory != _selectedCategory;
    setState(() {
      _filters = value;
      _selectedCategory = newCategory;
    });
    if (categoryChanged) unawaited(_loadServices());
  }

  List<LocalServiceModel> get _visibleServices {
    final query = _searchQuery.trim().toLowerCase();
    final distance = _filters[DistanceFilter.groupId];
    final session = TenantSession.instance;
    return _services.where((service) {
      if (distance != null && distance.isNotEmpty) {
        final km = LocalDistance.km(
          session.centerLat,
          session.centerLng,
          service.lat,
          service.lng,
        );
        if (!DistanceFilter.matches(distance, km)) return false;
      }
      if (query.isEmpty) return true;
      return service.title.toLowerCase().contains(query) ||
          service.description.toLowerCase().contains(query) ||
          (service.publisherName?.toLowerCase().contains(query) ?? false);
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: () async {
        await _sync.syncNow();
        await _loadServices();
      },
      child: ListView(
        key: const ValueKey('services_directory_list'),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          Text('Servicios del barrio', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            _emergency
                ? '¿Quién puede ayudar ahora? Los primeros están más preparados y más cerca.'
                : 'Encuentra y recomienda oficios de tus vecinos.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          // Bajo estrés la atención se estrecha: lo urgente va antes que buscar.
          if (_emergency &&
              _loadError == null &&
              _visibleServices.isNotEmpty) ...[
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: Column(
                key: const ValueKey('services_podium_first'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _buildPodium(context),
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (_merchant.isMerchant) ...[
            FilledButton.icon(
              key: const ValueKey('offer_service_button'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
              ),
              onPressed: () => unawaited(_openOffer()),
              icon: const Icon(Icons.storefront_rounded),
              label: const Text('Ofrecer servicio'),
            ),
            const SizedBox(height: 16),
          ],
          SearchFilterBar(
            searchFieldKey: const ValueKey('services_search'),
            filterButtonKey: const ValueKey('services_filters_button'),
            hintText: 'Buscar oficio o vecino',
            onSearchChanged: (value) => setState(() => _searchQuery = value),
            groups: _filterGroups,
            selection: _filters,
            onFiltersChanged: _applyFilters,
          ),
          if (widget.emergencyOnly) ...[
            const SizedBox(height: 8),
            const Chip(
              avatar: Icon(Icons.health_and_safety_rounded),
              label: Text('Disponibles en emergencia'),
            ),
          ],
          const SizedBox(height: 12),
          if (_loadError != null)
            _buildMessage(
              context,
              icon: Icons.error_outline_rounded,
              message: 'No se pudieron cargar los servicios: $_loadError',
              action: TextButton(
                onPressed: () => unawaited(_loadServices()),
                child: const Text('Reintentar'),
              ),
            )
          else if (_isLoading && _services.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Center(child: Text('Cargando servicios…')),
              ),
            )
          else if (_visibleServices.isEmpty)
            _buildMessage(
              context,
              icon: Icons.handyman_outlined,
              message: _searchQuery.isNotEmpty ||
                      (_filters[DistanceFilter.groupId]?.isNotEmpty ?? false)
                  ? 'No encontramos servicios con esa búsqueda o esos filtros.'
                  : _selectedCategory == null
                  ? 'Todavía no hay servicios publicados en este barrio.'
                  : 'No hay servicios de ${ServiceCategory.labels[_selectedCategory]}.',
            )
          else
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: Column(
                key: ValueKey(
                  'services_list_${EmergencyModeProvider.instance.isActive.value}',
                ),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _buildServiceList(context),
              ),
            ),
        ],
      ),
    );
  }

  bool get _emergency => EmergencyModeProvider.instance.isActive.value;

  List<Ranked<LocalServiceModel>> get _podiumRanked {
    final session = TenantSession.instance;
    return EmergencyRanking.rankServices(
      _visibleServices,
      lat: session.centerLat,
      lng: session.centerLng,
    ).where((r) => r.isPodium).toList();
  }

  /// En emergencia, las 3 primeras según el ranking, con el marco
  /// "Prioridad 1/2/3". Se muestran arriba de todo (ver build).
  List<Widget> _buildPodium(BuildContext context) => [
    for (final r in _podiumRanked)
      Semantics(
        label: 'Prioridad ${r.priority} de 3',
        container: true,
        child: PodiumFrame(
          key: ValueKey('podium_service_${r.item.id}'),
          priority: r.priority!,
          child: _buildServiceCard(context, r.item),
        ),
      ),
  ];

  /// El resto de los servicios (en emergencia, sin los del podio).
  List<Widget> _buildServiceList(BuildContext context) {
    final services = _visibleServices;
    if (!_emergency) {
      return [for (final s in services) _buildServiceCard(context, s)];
    }
    final podiumIds = {for (final r in _podiumRanked) r.item.id};
    return [
      for (final s in services)
        if (!podiumIds.contains(s.id)) _buildServiceCard(context, s),
    ];
  }

  Widget _buildServiceCard(BuildContext context, LocalServiceModel service) {
    final endorsement = _myEndorsements[service.id];
    final isOwnService = service.providerUserId == _userId;
    return ServiceCard(
      key: ValueKey('service_${service.id}'),
      title: service.publisherName?.isNotEmpty == true
          ? '${service.publisherName}, ${service.title}'
          : service.title,
      categoryLabel:
          ServiceCategory.labels[service.category] ?? service.category,
      categoryIcon: ServiceCategoryUi.icon(service.category),
      description: service.description,
      endorsementsCount: service.endorsementsCount,
      ratingAvg: service.ratingAvg,
      isOwn: isOwnService,
      priceText: service.priceText,
      photoCount: service.photoCount,
      isEndorsed: endorsement != null,
      isPending: service.isPending || (endorsement?.isPending ?? false),
      isAvailableInEmergency: service.isAvailableInEmergency,
      onEndorse: isOwnService || _updatingEndorsements.contains(service.id)
          ? null
          : () => unawaited(_toggleEndorsement(service)),
      onTap: () => unawaited(
        showServiceDetailSheet(
          context,
          service: service,
          tenantId: _tenantId,
          userId: _userId,
          endorsementsDatasource: _endorsementsDatasource,
        ),
      ),
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
