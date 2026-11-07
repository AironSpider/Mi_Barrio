import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/barrio_context/tenant_session.dart';
import '../../../../core/database_sqlite/sync_outbox_dao.dart';
import '../../../../core/sync_manager/sync_coordinator.dart';
import '../../../../core/ui_kit/star_rating_display.dart';
import '../../data/datasources/endorsements_sqlite_ds.dart';
import '../../data/datasources/services_sqlite_ds.dart';
import '../../data/models/endorsement_model.dart';
import '../../data/models/service_model.dart';
import '../widgets/service_card.dart';

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
  static const _categories = <String?>[
    null,
    ServiceCategory.gasfiteria,
    ServiceCategory.carpinteria,
    ServiceCategory.electricidad,
    ServiceCategory.clases,
    ServiceCategory.paseadorMascotas,
  ];

  static const _icons = <String, IconData>{
    ServiceCategory.gasfiteria: Icons.plumbing_rounded,
    ServiceCategory.carpinteria: Icons.carpenter_rounded,
    ServiceCategory.electricidad: Icons.electrical_services_rounded,
    ServiceCategory.clases: Icons.school_rounded,
    ServiceCategory.paseadorMascotas: Icons.pets_rounded,
  };

  late final String _tenantId;
  late final String _userId;
  late final ServicesSqliteDatasource _servicesDatasource;
  late final EndorsementsSqliteDatasource _endorsementsDatasource;
  late final SyncCoordinator _sync;
  late final StreamSubscription<String> _queueSubscription;

  String? _selectedCategory;
  String _searchQuery = '';
  List<LocalServiceModel> _services = const [];
  final Map<String, EndorsementModel> _myEndorsements = {};
  final Set<String> _updatingEndorsements = {};
  bool _isLoading = true;
  String? _loadError;
  int _loadVersion = 0;

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
    _queueSubscription = SyncOutboxDao.onQueued.listen((tenantId) {
      if (tenantId == _tenantId) _loadServices();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_loadServices());
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
    unawaited(_queueSubscription.cancel());
    super.dispose();
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

  List<LocalServiceModel> get _visibleServices {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return _services;
    return _services
        .where(
          (service) =>
              service.title.toLowerCase().contains(query) ||
              service.description.toLowerCase().contains(query) ||
              (service.publisherName?.toLowerCase().contains(query) ?? false),
        )
        .toList(growable: false);
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
            'Encuentra y recomienda oficios de tus vecinos.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('services_search'),
            onChanged: (value) => setState(() => _searchQuery = value),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: 'Buscar oficio o vecino',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('Oficios', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final category in _categories)
                ChoiceChip(
                  key: ValueKey('service_category_${category ?? 'all'}'),
                  label: Text(
                    category == null ? 'Todos' : _categoryLabel(category),
                  ),
                  selected: _selectedCategory == category,
                  selectedColor: theme.colorScheme.primary,
                  labelStyle: TextStyle(
                    color: _selectedCategory == category
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.onSurface,
                  ),
                  onSelected: (_) {
                    setState(() => _selectedCategory = category);
                    unawaited(_loadServices());
                  },
                ),
            ],
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
              message: _searchQuery.isNotEmpty
                  ? 'No encontramos servicios para esa búsqueda.'
                  : _selectedCategory == null
                  ? 'Todavía no hay servicios publicados en este barrio.'
                  : 'No hay servicios de ${ServiceCategory.labels[_selectedCategory]}.',
            )
          else
            for (final service in _visibleServices)
              _buildServiceCard(context, service),
        ],
      ),
    );
  }

  Widget _buildServiceCard(BuildContext context, LocalServiceModel service) {
    final endorsement = _myEndorsements[service.id];
    final isOwnService = service.providerUserId == _userId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ServiceCard(
          key: ValueKey('service_${service.id}'),
          title: service.publisherName?.isNotEmpty == true
              ? '${service.publisherName}, ${service.title}'
              : service.title,
          categoryLabel:
              ServiceCategory.labels[service.category] ?? service.category,
          categoryIcon: _icons[service.category] ?? Icons.handyman_rounded,
          description: service.description,
          endorsementsCount: service.endorsementsCount,
          isEndorsed: endorsement != null,
          isPending: service.isPending || (endorsement?.isPending ?? false),
          isAvailableInEmergency: service.isAvailableInEmergency,
          onEndorse: isOwnService || _updatingEndorsements.contains(service.id)
              ? null
              : () => unawaited(_toggleEndorsement(service)),
        ),
        if (service.ratingAvg != null)
          Padding(
            padding: const EdgeInsets.only(left: 20, bottom: 8),
            child: StarRatingDisplay(
              rating: service.ratingAvg!,
              count: service.endorsementsCount,
            ),
          ),
        if (isOwnService)
          Padding(
            padding: const EdgeInsets.only(left: 20, bottom: 8),
            child: Text(
              'Este es tu servicio',
              style: Theme.of(context).textTheme.labelMedium,
            ),
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

  String _categoryLabel(String category) => switch (category) {
    ServiceCategory.gasfiteria => 'Gasfitería',
    ServiceCategory.carpinteria => 'Carpintería',
    ServiceCategory.electricidad => 'Electricidad',
    ServiceCategory.clases => 'Clases',
    ServiceCategory.paseadorMascotas => 'Mascotas',
    _ => ServiceCategory.labels[category] ?? category,
  };
}
