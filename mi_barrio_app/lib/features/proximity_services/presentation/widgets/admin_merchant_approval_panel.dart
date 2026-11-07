import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/barrio_context/tenant_session.dart';
import '../../data/datasources/admin_merchant_approval_remote_ds.dart';

class AdminMerchantApprovalPanel extends StatefulWidget {
  const AdminMerchantApprovalPanel({super.key, this.datasource});

  final AdminMerchantApprovalRemoteDatasource? datasource;

  @override
  State<AdminMerchantApprovalPanel> createState() =>
      _AdminMerchantApprovalPanelState();
}

class _AdminMerchantApprovalPanelState
    extends State<AdminMerchantApprovalPanel> {
  late final AdminMerchantApprovalRemoteDatasource _datasource;
  List<Map<String, dynamic>> _pending = const [];
  bool _loading = true;
  final Set<String> _working = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _datasource = widget.datasource ?? AdminMerchantApprovalRemoteDatasource();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final merchants = await _datasource.pendingMerchants(
        TenantSession.instance.tenantId,
      );
      if (!mounted) return;
      setState(() {
        _pending = merchants;
        _loading = false;
      });
    } catch (error, stackTrace) {
      debugPrint(
        'No se pudieron cargar comerciantes pendientes: $error\n$stackTrace',
      );
      if (!mounted) return;
      setState(() {
        _error = 'No pudimos cargar los servicios pendientes.';
        _loading = false;
      });
    }
  }

  Future<void> _review(String serviceId, {required bool approve}) async {
    if (!_working.add(serviceId)) return;
    setState(() {});
    try {
      if (approve) {
        await _datasource.approve(TenantSession.instance.tenantId, serviceId);
      } else {
        await _datasource.reject(TenantSession.instance.tenantId, serviceId);
      }
      await _load();
      if (mounted) {
        _show(
          approve
              ? 'Comerciante aprobado.'
              : 'Solicitud de comerciante rechazada.',
        );
      }
    } catch (error, stackTrace) {
      debugPrint('No se pudo revisar al comerciante: $error\n$stackTrace');
      if (mounted) _show('No pudimos completar la acción. Intenta de nuevo.');
    } finally {
      _working.remove(serviceId);
      if (mounted) setState(() {});
    }
  }

  void _show(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Comerciantes por aprobar',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: 'Actualizar solicitudes de comerciantes',
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_error != null)
            TextButton(onPressed: _load, child: Text('$_error Reintentar'))
          else if (_pending.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No hay comerciantes pendientes de aprobación.'),
            )
          else
            for (final merchant in _pending) _merchantItem(context, merchant),
        ],
      ),
    ),
  );

  Widget _merchantItem(BuildContext context, Map<String, dynamic> merchant) {
    final id = merchant['id']?.toString() ?? '';
    final working = _working.contains(id);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(merchant['full_name']?.toString() ?? 'Comerciante'),
      subtitle: Text(merchant['email']?.toString() ?? 'Correo no disponible'),
      trailing: working
          ? const SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Wrap(
              spacing: 4,
              children: [
                IconButton(
                  tooltip: 'Rechazar solicitud de comerciante',
                  onPressed: () => _review(id, approve: false),
                  icon: const Icon(Icons.close_rounded),
                ),
                IconButton(
                  tooltip: 'Aprobar comerciante',
                  onPressed: () => _review(id, approve: true),
                  icon: const Icon(Icons.check_rounded),
                ),
              ],
            ),
    );
  }
}
