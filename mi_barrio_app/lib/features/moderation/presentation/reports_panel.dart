import 'dart:async';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/ui_kit/app_theme.dart';
import '../data/content_reports.dart';

/// Panel "Reportes" para el administrador del barrio ([tenantId]) o el
/// superadministrador (sin [tenantId]: todos los barrios).
/// Con 3 reportes de vecinos distintos la publicación ya está oculta
/// ("En revisión"); aquí se decide si vuelve a mostrarse o se elimina.
class ReportsPanelCard extends StatefulWidget {
  const ReportsPanelCard({super.key, this.tenantId, this.datasource});

  final String? tenantId;
  final ModerationRemoteDatasource? datasource;

  static const cardKey = ValueKey('reports_panel');

  @override
  State<ReportsPanelCard> createState() => _ReportsPanelCardState();
}

class _ReportsPanelCardState extends State<ReportsPanelCard> {
  late final ModerationRemoteDatasource _ds =
      widget.datasource ?? ModerationRemoteDatasource(tenantId: widget.tenantId);
  List<ReportedItem> _items = const [];
  bool _loading = true;
  String? _error;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _ds.list();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'No se pudieron cargar los reportes. Revisa tu conexión e intenta de nuevo.';
      });
    }
  }

  Future<void> _resolve(ReportedItem item, String action) async {
    if (action == 'remove') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('¿Eliminar esta publicación?'),
          content: Text('"${item.title}" dejará de verse en el barrio. No se puede deshacer.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppPalette.urgencyCritical,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Eliminar'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy.add(item.targetId));
    try {
      await _ds.resolve(item, action);
      if (!mounted) return;
      setState(() => _items = [for (final i in _items) if (i.targetId != item.targetId) i]);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              action == 'remove'
                  ? 'Publicación eliminada.'
                  : 'Publicación restaurada: los vecinos la vuelven a ver.',
            ),
          ),
        );
    } catch (_) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('No se pudo guardar. Intenta de nuevo.')));
    } finally {
      if (mounted) setState(() => _busy.remove(item.targetId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    final count = _items.length;
    return Card(
      key: ReportsPanelCard.cardKey,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 8, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const FaIcon(FontAwesomeIcons.solidFlag, size: 18, color: AppPalette.urgencyCritical),
                const SizedBox(width: 10),
                Text('Reportes', style: texto.titleMedium),
                const SizedBox(width: 8),
                if (count > 0)
                  Semantics(
                    label: '$count publicaciones reportadas',
                    excludeSemantics: true,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppPalette.urgencyCritical,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$count',
                        style: texto.labelMedium?.copyWith(color: Colors.white),
                      ),
                    ),
                  ),
                const Spacer(),
                IconButton(
                  tooltip: 'Actualizar reportes',
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(
                'Con 3 reportes de vecinos distintos la publicación se oculta '
                'hasta que decidas.',
                style: texto.bodyMedium,
              ),
            ),
            const SizedBox(height: 8),
            if (_loading)
              Padding(
                padding: const EdgeInsets.only(right: 12, top: 8),
                child: Text('Cargando reportes…', style: texto.bodyMedium),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.only(right: 12, top: 8),
                child: Text(_error!, style: texto.bodyMedium),
              )
            else if (_items.isEmpty)
              Padding(
                padding: const EdgeInsets.only(right: 12, top: 8),
                child: Text('No hay publicaciones reportadas.', style: texto.bodyMedium),
              )
            else
              for (final item in _items)
                Padding(
                  padding: const EdgeInsets.only(right: 12, top: 12),
                  child: _ReportedTile(
                    item: item,
                    busy: _busy.contains(item.targetId),
                    onRestore: () => _resolve(item, 'restore'),
                    onRemove: () => _resolve(item, 'remove'),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _ReportedTile extends StatelessWidget {
  const _ReportedTile({
    required this.item,
    required this.busy,
    required this.onRestore,
    required this.onRemove,
  });

  final ReportedItem item;
  final bool busy;
  final VoidCallback onRestore;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppPalette.hover,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppPalette.filterActiveBackground),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _Tag(item.isService ? 'Servicio' : 'Favor del muro'),
              if (item.isUnderReview) const _Tag('En revisión: oculta', strong: true),
              _Tag('${item.reportCount} ${item.reportCount == 1 ? 'reporte' : 'reportes'}'),
              if (item.tenantName != null) _Tag(item.tenantName!),
            ],
          ),
          const SizedBox(height: 8),
          Text(item.title, style: texto.titleSmall),
          if (item.description?.trim().isNotEmpty ?? false)
            Text(
              item.description!.trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: texto.bodyMedium,
            ),
          const SizedBox(height: 6),
          for (final reason in item.reasons)
            Text('• $reason', style: texto.bodyMedium),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: busy ? null : onRestore,
                  child: const Text('Restaurar'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppPalette.urgencyCritical,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: busy ? null : onRemove,
                  child: const Text('Eliminar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label, {this.strong = false});

  final String label;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: strong ? AppPalette.failedBackground : AppPalette.card,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: strong ? AppPalette.urgencyCritical : AppPalette.textPrimary,
        ),
      ),
    );
  }
}
