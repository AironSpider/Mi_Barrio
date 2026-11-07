import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/barrio_context/tenant_session.dart';
import '../../../../core/ui_kit/app_theme.dart';
import '../../domain/entities/vulnerable_report_entity.dart';
import '../providers/emergency_provider.dart';

/// Abre el flujo SOS (Clic 1 = botón "Pedir ayuda").
/// Devuelve true si se guardó el pedido.
Future<bool> showSosSheet(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => const SosSheet(),
  );
  if (saved == true) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Pedido de ayuda guardado. Se enviará apenas haya señal.'),
        ),
      );
  }
  return saved == true;
}

/// Hoja "Pedir ayuda":
/// - Clic 2: elegir qué pasa (tarjetas grandes con ícono y texto).
/// - Clic 3: "Enviar pedido de ayuda".
/// La urgencia se sugiere sola según el tipo y el detalle es opcional.
class SosSheet extends StatefulWidget {
  const SosSheet({super.key});

  static const sendButtonKey = ValueKey('sos_send_button');

  @override
  State<SosSheet> createState() => _SosSheetState();
}

class _SosSheetState extends State<SosSheet> {
  static const _icons = {
    VulnerabilityType.atencionMedica: Icons.medical_services_rounded,
    VulnerabilityType.adultoMayorSolo: Icons.elderly_rounded,
    VulnerabilityType.movilidadReducida: Icons.accessible_rounded,
    VulnerabilityType.viviendaAfectada: Icons.house_siding_rounded,
    VulnerabilityType.faltaSuministros: Icons.water_drop_rounded,
  };

  final _detalle = TextEditingController();
  String? _tipo;
  String _urgencia = UrgencyLevel.alta;
  bool _enviando = false;
  String? _error;

  @override
  void dispose() {
    _detalle.dispose();
    super.dispose();
  }

  void _elegir(String tipo) {
    HapticFeedback.selectionClick();
    setState(() {
      _tipo = tipo;
      _urgencia = VulnerabilityType.defaultUrgency(tipo);
    });
  }

  Future<void> _enviar() async {
    final tipo = _tipo;
    if (tipo == null || _enviando) return;
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      final ubicacion = await HelpLocator.resolve();
      final session = TenantSession.instance;
      await EmergencyReports.repository.createSos(
        tenantId: session.tenantId,
        reporterUserId: session.userId,
        vulnerabilityType: tipo,
        urgencyLevel: _urgencia,
        description: _detalle.text,
        lat: ubicacion.lat,
        lng: ubicacion.lng,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _error = 'No se pudo guardar el pedido. Intenta de nuevo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    final esquema = Theme.of(context).colorScheme;
    final teclado = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: teclado),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Pedir ayuda', style: texto.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Tus vecinos verán tu pedido aunque no tengas internet ahora.',
              style: texto.bodyMedium?.copyWith(color: esquema.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Text('¿Qué está pasando?', style: texto.titleMedium),
            const SizedBox(height: 12),
            for (final tipo in VulnerabilityType.labels.keys) ...[
              _TipoTile(
                key: ValueKey('sos_type_$tipo'),
                icon: _icons[tipo]!,
                label: VulnerabilityType.labels[tipo]!,
                selected: _tipo == tipo,
                onTap: () => _elegir(tipo),
              ),
              const SizedBox(height: 8),
            ],
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              alignment: Alignment.topCenter,
              child: _tipo == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Urgencia', style: texto.titleMedium),
                          const SizedBox(height: 8),
                          SegmentedButton<String>(
                            showSelectedIcon: false,
                            style: SegmentedButton.styleFrom(
                              minimumSize: const Size(48, 52),
                            ),
                            segments: [
                              for (final nivel in UrgencyLevel.labels.keys)
                                ButtonSegment(
                                  value: nivel,
                                  label: Text(UrgencyLevel.labels[nivel]!),
                                ),
                            ],
                            selected: {_urgencia},
                            onSelectionChanged: (v) =>
                                setState(() => _urgencia = v.first),
                          ),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _detalle,
                            maxLength: 200,
                            textCapitalization: TextCapitalization.sentences,
                            style: texto.bodyLarge,
                            decoration: InputDecoration(
                              labelText: 'Detalle (opcional)',
                              hintText: 'Ej: Vivo en la casa azul, 2do piso',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: texto.bodyMedium?.copyWith(color: esquema.error)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              key: SosSheet.sendButtonKey,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                backgroundColor: AppPalette.emergencyPrimary,
                foregroundColor: AppPalette.emergencyOnPrimary,
              ),
              onPressed: _tipo == null || _enviando ? null : _enviar,
              child: Text(_enviando ? 'Guardando…' : 'Enviar pedido de ayuda'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TipoTile extends StatelessWidget {
  const _TipoTile({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    final fondo = selected ? AppPalette.emergencyBackground : AppPalette.card;
    final frente = selected
        ? AppPalette.emergencyOnPrimaryContainer
        : AppPalette.textPrimary;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: fondo,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: selected ? AppPalette.emergencyStripe : const Color(0xFFE2E8F0),
            width: selected ? 2 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Icon(icon, size: 28, color: frente),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(label, style: texto.titleMedium?.copyWith(color: frente)),
                  ),
                  if (selected)
                    const Icon(
                      Icons.check_circle_rounded,
                      color: AppPalette.emergencyOnPrimaryContainer,
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
