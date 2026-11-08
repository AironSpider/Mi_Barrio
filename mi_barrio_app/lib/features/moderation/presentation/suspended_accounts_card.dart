import 'dart:async';

import 'package:flutter/material.dart';

import '../data/suspended_accounts.dart';

/// Para el jefe del barrio: vecinos suspendidos por reportes y el botón para
/// reactivarlos después de hablar con ellos.
class SuspendedAccountsCard extends StatefulWidget {
  const SuspendedAccountsCard({super.key, required this.tenantId, this.datasource});

  final String tenantId;
  final SuspendedAccountsDatasource? datasource;

  static const cardKey = ValueKey('suspended_accounts_card');
  static ValueKey<String> reactivateKey(String userId) =>
      ValueKey('reactivate_$userId');

  @override
  State<SuspendedAccountsCard> createState() => _SuspendedAccountsCardState();
}

class _SuspendedAccountsCardState extends State<SuspendedAccountsCard> {
  late final SuspendedAccountsDatasource _ds =
      widget.datasource ?? SuspendedAccountsDatasource(tenantId: widget.tenantId);
  List<SuspendedAccount> _items = const [];
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
        _error = 'No se pudieron cargar las cuentas suspendidas. Revisa tu conexión.';
      });
    }
  }

  Future<void> _reactivate(SuspendedAccount account) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('¿Reactivar a ${account.fullName}?'),
        content: const Text(
          'Hazlo después de conversar con el vecino. Podrá volver a usar la app '
          'y sus reportes anteriores ya no cuentan: hacen falta 3 reportes nuevos '
          'para volver a suspenderlo.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reactivar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy.add(account.userId));
    try {
      await _ds.reactivate(account.userId);
      if (!mounted) return;
      setState(() => _items = [for (final a in _items) if (a.userId != account.userId) a]);
      messenger.showSnackBar(
        SnackBar(content: Text('${account.fullName} ya puede volver a usar Mi Barrio.')),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No se pudo reactivar. Revisa tu conexión e intenta de nuevo.')),
      );
    } finally {
      if (mounted) setState(() => _busy.remove(account.userId));
    }
  }

  static String _date(DateTime? d) => d == null
      ? ''
      : ' · desde el ${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      key: SuspendedAccountsCard.cardKey,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.person_off_rounded, color: theme.colorScheme.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Cuentas suspendidas', style: theme.textTheme.titleMedium),
                ),
                IconButton(
                  tooltip: 'Actualizar',
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            Text(
              'Se suspenden solas cuando 3 vecinos distintos reportan sus '
              'publicaciones. Habla con la persona antes de reactivarla.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
            else if (_error != null)
              Row(
                children: [
                  Expanded(child: Text(_error!)),
                  TextButton(onPressed: _load, child: const Text('Reintentar')),
                ],
              )
            else if (_items.isEmpty)
              const Text('No hay cuentas suspendidas. 👍')
            else
              for (final a in _items)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(a.fullName),
                  subtitle: Text(
                    '${a.email ?? ''}\nReportado por ${a.reportCount} vecinos${_date(a.suspendedAt)}',
                  ),
                  isThreeLine: true,
                  trailing: _busy.contains(a.userId)
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5))
                      : FilledButton.tonal(
                          key: SuspendedAccountsCard.reactivateKey(a.userId),
                          onPressed: () => _reactivate(a),
                          child: const Text('Reactivar'),
                        ),
                ),
          ],
        ),
      ),
    );
  }
}
