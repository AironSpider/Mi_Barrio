import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/barrio_context/tenant_session.dart';
import '../../../../core/sync_manager/sync_coordinator.dart';
import '../../../../shared/contact_launcher.dart';
import '../../../../shared/local_distance.dart';
import '../../../emergency_support/data/datasources/support_groups_sqlite_ds.dart';
import '../../../emergency_support/data/models/support_group_model.dart';

/// "Grupos de apoyo" del barrio (se muestra en Apoyo durante la emergencia).
/// Lee del teléfono, así que funciona sin señal; ordena del más cercano al más lejano.
class SupportGroupsSection extends StatefulWidget {
  const SupportGroupsSection({super.key, this.datasource, this.tenantId, this.lat, this.lng});

  final SupportGroupsSqliteDatasource? datasource;
  final String? tenantId;
  final double? lat;
  final double? lng;

  static const sectionKey = ValueKey('support_groups_section');

  @override
  State<SupportGroupsSection> createState() => _SupportGroupsSectionState();
}

class _SupportGroupsSectionState extends State<SupportGroupsSection> {
  late final SupportGroupsSqliteDatasource _ds = widget.datasource ?? SupportGroupsSqliteDatasource();
  final _sync = SyncCoordinator.instance;
  List<SupportGroupModel> _groups = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _sync.phase.addListener(_onSync);
    unawaited(_load());
  }

  @override
  void dispose() {
    _sync.phase.removeListener(_onSync);
    super.dispose();
  }

  // Los grupos llegan con el pull: al terminar un sync se vuelven a leer.
  void _onSync() {
    if (_sync.phase.value == SyncPhase.idle) unawaited(_load());
  }

  Future<void> _load() async {
    final session = TenantSession.instance;
    try {
      final groups = await _ds.activeGroups(
        widget.tenantId ?? session.tenantId,
        lat: widget.lat ?? session.centerLat,
        lng: widget.lng ?? session.centerLng,
      );
      if (mounted) setState(() => _groups = groups);
    } catch (_) {
      // Sin grupos guardados todavía: la sección muestra el aviso vacío.
    }
    if (mounted) setState(() => _loaded = true);
  }

  Future<void> _copy(SupportGroupModel g) async {
    await Clipboard.setData(ClipboardData(text: g.contactPhone!.trim()));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Número de ${g.name} copiado')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      child: Column(
        key: SupportGroupsSection.sectionKey,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.groups_rounded, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text('Grupos de apoyo', style: theme.textTheme.titleLarge),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('Brigadas, albergues y ollas comunes de tu barrio, del más cercano al más lejano.',
              style: theme.textTheme.bodyMedium),
          const SizedBox(height: 8),
          if (!_loaded)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_groups.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Tu junta vecinal aún no registró grupos de apoyo.',
                    style: theme.textTheme.bodyMedium),
              ),
            )
          else
            for (final g in _groups) _GroupCard(group: g, onCopy: g.hasPhone ? () => _copy(g) : null),
        ],
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group, required this.onCopy});

  final SupportGroupModel group;
  final VoidCallback? onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final distance = group.distanceKm;
    return Card(
      key: ValueKey('support_group_${group.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(group.name, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Chip(label: Text(group.typeLabel)),
                if (distance != null)
                  Text('a ${LocalDistance.label(distance)}', style: theme.textTheme.bodyMedium),
              ],
            ),
            if (group.meetingPoint != null && group.meetingPoint!.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.place_rounded, size: 20),
                  const SizedBox(width: 6),
                  Expanded(child: Text(group.meetingPoint!, style: theme.textTheme.bodyMedium)),
                ],
              ),
            ],
            if (onCopy != null) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: 8,
                children: [
                  // Llamar es la acción principal (un toque); copiar queda de respaldo.
                  Semantics(
                    button: true,
                    label: 'Llamar a ${group.name}',
                    excludeSemantics: true,
                    child: FilledButton.icon(
                      key: ValueKey('support_group_call_${group.id}'),
                      style: FilledButton.styleFrom(minimumSize: const Size(120, 48)),
                      onPressed: () async {
                        final ok = await ContactLauncher.call(group.contactPhone!);
                        if (!ok) onCopy?.call();
                      },
                      icon: const Icon(Icons.call_rounded),
                      label: const Text('Llamar'),
                    ),
                  ),
                  Text(group.contactPhone!, style: theme.textTheme.titleSmall),
                  TextButton.icon(
                    onPressed: onCopy,
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('Copiar número'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
