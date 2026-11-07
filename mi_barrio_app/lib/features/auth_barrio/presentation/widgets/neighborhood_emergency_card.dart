import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/ui_kit/emergency_toggle.dart';

/// Tarjeta del administrador del barrio para activar el Modo Emergencia de TODOS.
/// Los celulares de los vecinos lo reciben en su siguiente sincronización.
class NeighborhoodEmergencyCard extends StatefulWidget {
  const NeighborhoodEmergencyCard({super.key, required this.tenantId, this.client});

  final String tenantId;
  final ApiClient? client;

  @override
  State<NeighborhoodEmergencyCard> createState() => _NeighborhoodEmergencyCardState();
}

class _NeighborhoodEmergencyCardState extends State<NeighborhoodEmergencyCard> {
  late final ApiClient _api = widget.client ?? ApiClient();
  bool? _active;
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await _api.get('/api/v1/tenants/current', widget.tenantId);
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _active = data['is_emergency_active'] == true;
        _busy = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'No se pudo consultar el estado. Revisa tu conexión.';
      });
    }
  }

  Future<void> _change(bool value) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(value ? '¿Activar Modo Emergencia?' : '¿Desactivar Modo Emergencia?'),
        content: Text(
          value
              ? 'Esto activará la emergencia para TODO el barrio. Los vecinos verán '
                    'el tablero de ayuda y el botón "Pedir ayuda".'
              : 'El barrio volverá al modo normal.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(value ? 'Activar' : 'Desactivar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final r = await _api.patch(
        '/api/v1/tenants/emergency-toggle',
        widget.tenantId,
        {'is_emergency_active': value},
      );
      if (r.statusCode != 200) throw Exception('HTTP ${r.statusCode}');
      if (!mounted) return;
      setState(() {
        _active = value;
        _busy = false;
        _error = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(value
              ? 'Emergencia activada. Los vecinos la verán en segundos.'
              : 'Emergencia desactivada.'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'No se pudo cambiar. Se necesita conexión con el servidor.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Emergencia del barrio', style: texto.titleMedium),
            const SizedBox(height: 12),
            EmergencyToggle(
              value: _active ?? false,
              onChanged: _busy || _active == null ? null : _change,
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: texto.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
    );
  }
}
