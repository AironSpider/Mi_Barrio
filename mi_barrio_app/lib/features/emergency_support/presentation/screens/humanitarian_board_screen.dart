import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/barrio_context/tenant_session.dart';
import '../../../../core/ui_kit/dev_tools.dart';
import '../../../../shared/local_distance.dart';
import '../../domain/entities/vulnerable_report_entity.dart';
import '../../domain/repositories/emergency_repository.dart';
import '../providers/emergency_provider.dart';
import '../widgets/help_report_card.dart';

/// Tablero de ayuda humanitaria.
///
/// - [sortByDistance] = false: por urgencia (Crítica → Alta → Media) y, dentro de
///   cada nivel, primero los que aún necesitan apoyo y los más recientes.
/// - [sortByDistance] = true: del más cercano al más lejano (Mapa en modo lista).
class HumanitarianBoardScreen extends StatefulWidget {
  const HumanitarianBoardScreen({
    super.key,
    required this.isEmergencyMode,
    this.sortByDistance = false,
    this.repository,
    this.header,
  });

  final bool isEmergencyMode;
  final bool sortByDistance;
  final EmergencyRepository? repository;

  /// Contenido opcional arriba de la lista (lo usa el Mapa).
  final Widget? header;

  @override
  State<HumanitarianBoardScreen> createState() => _HumanitarianBoardScreenState();
}

class _HumanitarianBoardScreenState extends State<HumanitarianBoardScreen> {
  late final EmergencyRepository _repository;
  StreamSubscription<void>? _changes;
  List<VulnerableReport> _reports = const [];
  HelpLocation? _location;
  bool _loading = true;
  String? _error;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? EmergencyReports.repository;
    _changes = _repository.changes.listen((_) => _load());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_load());
      unawaited(_resolveLocation());
    });
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    super.dispose();
  }

  Future<void> _resolveLocation() async {
    final location = await HelpLocator.resolve();
    if (mounted) setState(() => _location = location);
  }

  Future<void> _load() async {
    try {
      final reports = await _repository.activeReports(TenantSession.instance.tenantId);
      if (!mounted) return;
      setState(() {
        _reports = reports;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No se pudieron cargar los pedidos de ayuda.';
      });
    }
  }

  double? _km(VulnerableReport r) {
    final loc = _location;
    if (loc == null) return null;
    return LocalDistance.km(loc.lat, loc.lng, r.lat, r.lng);
  }

  List<VulnerableReport> get _sorted {
    final list = _reports.where((r) => r.status != ReportStatus.atendido).toList();
    int byNeed(VulnerableReport a, VulnerableReport b) =>
        (a.needsHelp ? 0 : 1).compareTo(b.needsHelp ? 0 : 1);
    if (widget.sortByDistance && _location != null) {
      list.sort((a, b) {
        final d = _km(a)!.compareTo(_km(b)!);
        return d != 0 ? d : UrgencyLevel.rank(a.urgencyLevel).compareTo(UrgencyLevel.rank(b.urgencyLevel));
      });
    } else {
      list.sort((a, b) {
        final u = UrgencyLevel.rank(a.urgencyLevel).compareTo(UrgencyLevel.rank(b.urgencyLevel));
        if (u != 0) return u;
        final n = byNeed(a, b);
        return n != 0 ? n : b.updatedAt.compareTo(a.updatedAt);
      });
    }
    return list;
  }

  Future<void> _offerHelp(VulnerableReport report) async {
    setState(() => _busy.add(report.id));
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _repository.offerHelp(
        tenantId: TenantSession.instance.tenantId,
        reportId: report.id,
        helperUserId: TenantSession.instance.userId,
      );
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Gracias. Tus vecinos sabrán que vas en camino.')));
    } catch (_) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('No se pudo registrar tu ayuda. Intenta de nuevo.')));
    } finally {
      if (mounted) setState(() => _busy.remove(report.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    final esquema = Theme.of(context).colorScheme;
    final reports = _sorted;
    final me = TenantSession.instance.userId;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 112),
        children: [
          if (widget.header != null) widget.header!,
          if (widget.header == null) ...[
            Text(
              widget.isEmergencyMode ? 'Pedidos de ayuda' : 'Barrio preparado',
              style: texto.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              widget.isEmergencyMode
                  ? 'Ordenados por urgencia. Ofrece ayuda si puedes llegar.'
                  : 'No hay una emergencia activa. Si un vecino pide ayuda, aparecerá aquí.',
              style: texto.bodyMedium?.copyWith(color: esquema.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
          ],
          if (DevTools.enabled && EmergencyReports.isTemporary)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'Desarrollo: pedidos en memoria hasta conectar la tabla local de Dev 2.',
                style: texto.bodySmall?.copyWith(color: esquema.onSurfaceVariant),
              ),
            ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            _Message(icon: Icons.error_outline_rounded, text: _error!)
          else if (reports.isEmpty)
            _Message(
              icon: Icons.verified_user_rounded,
              text: widget.isEmergencyMode
                  ? 'Nadie ha pedido ayuda todavía. Si necesitas algo, toca "Pedir ayuda".'
                  : 'Tu barrio está tranquilo: no hay pedidos de ayuda.',
            )
          else
            for (final report in reports)
              HelpReportCard(
                key: ValueKey('help_report_${report.id}'),
                report: report,
                isMine: report.reporterUserId == me,
                distanceLabel: _km(report) == null ? null : 'a ${LocalDistance.label(_km(report)!)}',
                busy: _busy.contains(report.id),
                onOfferHelp: () => _offerHelp(report),
              ),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(icon, color: esquema.onSurfaceVariant, size: 28),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyLarge)),
          ],
        ),
      ),
    );
  }
}
