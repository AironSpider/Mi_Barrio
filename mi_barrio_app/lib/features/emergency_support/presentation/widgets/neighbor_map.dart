import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/barrio_context/tenant_session.dart';
import '../../../../core/database_sqlite/sync_outbox_dao.dart';
import '../../../../core/sync_manager/sync_coordinator.dart';
import '../../../../core/ui_kit/app_theme.dart';
import '../../../proximity_services/data/datasources/services_sqlite_ds.dart';
import '../../../proximity_services/data/models/service_model.dart';
import '../../../solidarity_network/data/datasources/solidarity_sqlite_ds.dart';
import '../../../solidarity_network/data/models/solidarity_post_model.dart';
import '../../domain/entities/vulnerable_report_entity.dart';
import '../../domain/neighbor_pins.dart';
import '../../domain/repositories/emergency_repository.dart';
import '../providers/emergency_provider.dart';

/// Mapa del barrio: un marcador por vecino con sus publicaciones activas
/// (pedidos de ayuda, favores y servicios). Al tocarlo, se ven todas.
///
/// Los datos salen del teléfono (funciona sin internet). Las calles del fondo
/// (OpenStreetMap) solo se ven con conexión; sin ella quedan los marcadores
/// sobre un fondo liso.
class NeighborMap extends StatefulWidget {
  const NeighborMap({
    super.key,
    required this.repository,
    this.location,
    this.servicesDatasource,
    this.solidarityDatasource,
    this.showStreets,
  });

  final EmergencyRepository repository;
  final HelpLocation? location;
  final ServicesSqliteDatasource? servicesDatasource;
  final SolidaritySqliteDatasource? solidarityDatasource;

  /// Calles de OpenStreetMap (por defecto sí, salvo en los tests: sin red).
  final bool? showStreets;

  static ValueKey<String> pinKey(String userId) => ValueKey('map_pin_$userId');

  @override
  State<NeighborMap> createState() => _NeighborMapState();
}

class _NeighborMapState extends State<NeighborMap> {
  late final ServicesSqliteDatasource _services =
      widget.servicesDatasource ?? ServicesSqliteDatasource();
  late final SolidaritySqliteDatasource _wall =
      widget.solidarityDatasource ?? SolidaritySqliteDatasource();
  final MapController _controller = MapController();
  StreamSubscription<void>? _reportsSub;
  StreamSubscription<String>? _queueSub;
  List<NeighborPin> _pins = const [];
  int _version = 0;

  bool get _showStreets =>
      widget.showStreets ?? !Platform.environment.containsKey('FLUTTER_TEST');

  @override
  void initState() {
    super.initState();
    _reportsSub = widget.repository.changes.listen((_) => _load());
    _queueSub = SyncOutboxDao.onQueued.listen((_) => _load());
    SyncCoordinator.instance.lastSuccess.addListener(_load);
    _load();
  }

  @override
  void didUpdateWidget(covariant NeighborMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final loc = widget.location;
    if (loc != null && loc != oldWidget.location) {
      try {
        _controller.move(LatLng(loc.lat, loc.lng), _controller.camera.zoom);
      } catch (_) {/* el mapa aún no se dibujó: usará la ubicación al iniciar */}
    }
  }

  @override
  void dispose() {
    unawaited(_reportsSub?.cancel());
    unawaited(_queueSub?.cancel());
    SyncCoordinator.instance.lastSuccess.removeListener(_load);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final version = ++_version;
    final session = TenantSession.instance;
    final byUser = <String, List<PinItem>>{};
    final labels = <String, String>{};
    void add(String userId, PinItem item) => byUser.putIfAbsent(userId, () => []).add(item);

    try {
      for (final r in await widget.repository.activeReports(session.tenantId)) {
        if (r.status == ReportStatus.atendido) continue;
        add(r.reporterUserId, PinItem(
          id: r.id,
          kind: PinItemKind.sos,
          title: VulnerabilityType.labels[r.vulnerabilityType] ?? 'Pide ayuda',
          subtitle: r.description != VulnerabilityType.labels[r.vulnerabilityType]
              ? r.description
              : ReportStatus.labels[r.status],
          lat: r.lat,
          lng: r.lng,
          updatedAt: r.updatedAt,
          canOfferHelp: r.needsHelp && r.reporterUserId != session.userId,
        ));
      }
    } catch (_) {/* sin SOS legibles: el resto del mapa igual se muestra */}
    try {
      for (final p in await _wall.getActivePosts(session.tenantId, includeCompleted: false)) {
        add(p.authorUserId, PinItem(
          id: p.id,
          kind: PinItemKind.favor,
          title: p.title,
          subtitle:
              '${p.flowType == SolidarityFlowType.ofrezcoAyuda ? 'Ofrece' : 'Necesita'} · '
              '${SolidarityModality.labels[p.modality] ?? p.modality}',
          lat: p.lat,
          lng: p.lng,
          updatedAt: p.updatedAt,
        ));
      }
      for (final s in await _services.getServices(session.tenantId)) {
        final name = s.publisherName?.trim();
        if (name != null && name.isNotEmpty) labels[s.providerUserId] = name;
        add(s.providerUserId, PinItem(
          id: s.id,
          kind: PinItemKind.service,
          title: s.title,
          subtitle: ServiceCategory.labels[s.category] ?? s.category,
          lat: s.lat,
          lng: s.lng,
          updatedAt: s.updatedAt,
        ));
      }
    } catch (_) {/* sin base local (tests): solo SOS */}

    if (!mounted || version != _version) return;
    setState(() {
      _pins = NeighborPins.build(
        itemsByUser: byUser,
        myUserId: session.userId,
        labels: labels,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = TenantSession.instance;
    final loc = widget.location;
    final center = LatLng(loc?.lat ?? session.centerLat, loc?.lng ?? session.centerLng);
    final colores = MiBarrioColors.of(context);
    final esquema = Theme.of(context).colorScheme;

    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: FlutterMap(
            mapController: _controller,
            options: MapOptions(
              initialCenter: center,
              initialZoom: 16.5,
              minZoom: 12,
              maxZoom: 19,
              backgroundColor: colores.accentSoft,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              if (_showStreets)
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  // = applicationId de Android (OpenStreetMap pide identificar la app).
                  userAgentPackageName: 'com.example.mi_barrio_app',
                  maxNativeZoom: 19,
                ),
              MarkerLayer(
                markers: [
                  if (loc != null && loc.fromGps)
                    Marker(
                      point: LatLng(loc.lat, loc.lng),
                      width: 26,
                      height: 26,
                      child: Semantics(
                        label: 'Tu ubicación',
                        child: Container(
                          decoration: BoxDecoration(
                            color: AppPalette.daySecondary,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 4),
                            boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black26)],
                          ),
                        ),
                      ),
                    ),
                  for (final pin in _pins)
                    Marker(
                      point: LatLng(pin.lat, pin.lng),
                      width: 56,
                      height: 56,
                      child: _PinMarker(
                        key: NeighborMap.pinKey(pin.userId),
                        pin: pin,
                        onTap: () => _openPin(pin),
                      ),
                    ),
                ],
              ),
              if (_showStreets)
                const SimpleAttributionWidget(
                  source: Text('© OpenStreetMap'),
                  backgroundColor: Color(0xCCFFFFFF),
                ),
            ],
          ),
        ),
        Positioned(
          left: 12,
          top: 12,
          right: 12,
          child: _Legend(count: _pins.length),
        ),
        Positioned(
          right: 12,
          bottom: 12,
          child: FloatingActionButton.small(
            heroTag: 'map_recenter',
            tooltip: 'Volver a mi zona',
            backgroundColor: esquema.surface,
            foregroundColor: esquema.primary,
            onPressed: () => _controller.move(center, 16.5),
            child: const Icon(Icons.my_location_rounded),
          ),
        ),
      ],
    );
  }

  Future<void> _openPin(NeighborPin pin) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _PinSheet(pin: pin, repository: widget.repository),
      );
}

Color _kindColor(BuildContext context, PinItemKind kind) {
  final colores = MiBarrioColors.of(context);
  return switch (kind) {
    PinItemKind.sos => colores.urgencyCritical,
    PinItemKind.service => AppPalette.daySecondary,
    PinItemKind.favor => AppPalette.dayPrimary,
  };
}

IconData _kindIcon(PinItemKind kind) => switch (kind) {
      PinItemKind.sos => Icons.sos_rounded,
      PinItemKind.service => Icons.handyman_rounded,
      PinItemKind.favor => Icons.volunteer_activism_rounded,
    };

String _kindLabel(PinItemKind kind) => switch (kind) {
      PinItemKind.sos => 'Pide ayuda',
      PinItemKind.service => 'Ofrece un servicio',
      PinItemKind.favor => 'Favor del muro',
    };

/// Marcador redondo de 48 dp (se toca fácil con una mano), con ícono según lo
/// más importante que publicó y un contador si tiene varias publicaciones.
class _PinMarker extends StatelessWidget {
  const _PinMarker({super.key, required this.pin, required this.onTap});

  final NeighborPin pin;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _kindColor(context, pin.mainKind);
    final n = pin.items.length;
    return Semantics(
      button: true,
      label: '${pin.label}: ${_kindLabel(pin.mainKind)}'
          '${n > 1 ? ', $n publicaciones' : ''}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: pin.isMe ? AppPalette.brandOrange : Colors.white,
                  width: pin.isMe ? 4 : 3,
                ),
                boxShadow: const [BoxShadow(blurRadius: 6, offset: Offset(0, 2), color: Colors.black26)],
              ),
              child: Icon(_kindIcon(pin.mainKind), color: Colors.white, size: 26),
            ),
            if (n > 1)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: color, width: 2),
                  ),
                  child: Text(
                    '$n',
                    style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    Widget item(PinItemKind kind) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_kindIcon(kind), size: 18, color: _kindColor(context, kind)),
            const SizedBox(width: 4),
            Flexible(child: Text(_kindLabel(kind), style: texto.labelMedium)),
          ],
        );
    return Material(
      color: Colors.white.withValues(alpha: 0.94),
      borderRadius: BorderRadius.circular(14),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              count == 0
                  ? 'Todavía no hay publicaciones en el mapa.'
                  : count == 1
                      ? '1 vecino publicando. Tócalo para ver qué ofrece o necesita.'
                      : '$count vecinos publicando. Toca uno para ver sus publicaciones.',
              style: texto.bodyMedium,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                item(PinItemKind.sos),
                item(PinItemKind.favor),
                item(PinItemKind.service),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Hoja con todo lo que publicó un vecino. En un SOS ajeno: "Voy en camino".
class _PinSheet extends StatefulWidget {
  const _PinSheet({required this.pin, required this.repository});

  final NeighborPin pin;
  final EmergencyRepository repository;

  @override
  State<_PinSheet> createState() => _PinSheetState();
}

class _PinSheetState extends State<_PinSheet> {
  final Set<String> _helped = {};
  String? _busy;

  Future<void> _offerHelp(PinItem item) async {
    setState(() => _busy = item.id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.repository.offerHelp(
        tenantId: TenantSession.instance.tenantId,
        reportId: item.id,
        helperUserId: TenantSession.instance.userId,
      );
      if (mounted) setState(() => _helped.add(item.id));
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Gracias. Tus vecinos sabrán que vas en camino.')));
    } catch (_) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('No se pudo registrar tu ayuda. Intenta de nuevo.')));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    final pin = widget.pin;
    final n = pin.items.length;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(pin.isMe ? 'Tus publicaciones' : pin.label, style: texto.titleLarge),
          Text(
            n == 1 ? '1 publicación activa' : '$n publicaciones activas',
            style: texto.bodyMedium,
          ),
          const SizedBox(height: 12),
          for (final item in pin.items)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(_kindIcon(item.kind), color: _kindColor(context, item.kind)),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _kindLabel(item.kind),
                            style: texto.labelLarge?.copyWith(color: _kindColor(context, item.kind)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(item.title, style: texto.titleMedium),
                    if (item.subtitle != null && item.subtitle!.isNotEmpty)
                      Text(item.subtitle!, style: texto.bodyMedium),
                    if (item.canOfferHelp) ...[
                      const SizedBox(height: 10),
                      _helped.contains(item.id)
                          ? Text('Vas en camino. ¡Gracias!', style: texto.labelLarge)
                          : FilledButton.icon(
                              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                              onPressed: _busy == null ? () => _offerHelp(item) : null,
                              icon: const Icon(Icons.directions_run_rounded),
                              label: const Text('Voy en camino'),
                            ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
