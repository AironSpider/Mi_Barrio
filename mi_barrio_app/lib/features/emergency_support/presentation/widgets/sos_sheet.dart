import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/barrio_context/tenant_session.dart';
import '../../../../core/database_sqlite/sqlite_database.dart';
import '../../../../core/ui_kit/app_theme.dart';
import '../../../../core/ui_kit/icon_scale.dart';
import '../../domain/entities/vulnerable_report_entity.dart';
import '../providers/emergency_provider.dart';
import '../../../../core/moderation/content_filter.dart';

/// Abre el flujo SOS (Clic 1 = botón "Ayuda").
/// Devuelve true si se guardó el pedido.
Future<bool> showSosSheet(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final result = await showModalBottomSheet<Object>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => const SosSheet(),
  );
  final saved = result == true || result == SosSheet.savedWithoutGps;
  if (saved) {
    // Sin GPS el pedido queda en el centro del barrio: hay que decirlo, si no
    // quien ayuda iría al lugar equivocado y el vecino no sabría por qué.
    final withoutGps = result == SosSheet.savedWithoutGps;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: Duration(seconds: withoutGps ? 10 : 4),
          content: Text(
            withoutGps
                ? 'Pedido de ayuda guardado, pero no pudimos usar tu ubicación: '
                      'se marcó en el centro del barrio. Si puedes, avisa a tus '
                      'vecinos dónde estás o activa la ubicación del teléfono.'
                : 'Pedido de ayuda guardado. Se enviará apenas haya señal.',
          ),
        ),
      );
  }
  return saved;
}

/// Hoja "Pedir ayuda":
/// - Clic 2: elegir qué pasa (tarjetas grandes con ícono y texto).
/// - Clic 3: "Enviar pedido de ayuda" (siempre a la vista, abajo).
/// La urgencia se sugiere sola según el tipo. Los datos de la urgencia
/// (personas, heridos, quiénes necesitan más cuidado, teléfono) son opcionales.
class SosSheet extends StatefulWidget {
  const SosSheet({super.key});

  static const sendButtonKey = ValueKey('sos_send_button');
  static const otherFieldKey = ValueKey('sos_other_label');
  static const peopleMinusKey = ValueKey('sos_people_minus');
  static const peoplePlusKey = ValueKey('sos_people_plus');
  static const phoneFieldKey = ValueKey('sos_phone');

  /// Valor con el que se cierra la hoja si se guardó sin la ubicación del GPS.
  static const savedWithoutGps = 'saved_without_gps';

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
    VulnerabilityType.inundacion: Icons.flood_rounded,
    VulnerabilityType.incendio: Icons.local_fire_department_rounded,
    VulnerabilityType.atrapados: Icons.lock_person_rounded,
    VulnerabilityType.otro: Icons.more_horiz_rounded,
  };

  final _detalle = TextEditingController();
  final _otro = TextEditingController();
  final _telefono = TextEditingController();
  String? _tipo;
  String _urgencia = UrgencyLevel.alta;
  int? _personas;
  bool? _heridos;
  final Set<String> _grupos = {};
  bool _enviando = false;
  String? _error;

  bool get _puedeEnviar =>
      _tipo != null &&
      !_enviando &&
      (_tipo != VulnerabilityType.otro || _otro.text.trim().isNotEmpty);

  @override
  void initState() {
    super.initState();
    _otro.addListener(() => setState(() {}));
    _cargarTelefono();
  }

  /// El teléfono del perfil ya viene escrito (se puede cambiar).
  Future<void> _cargarTelefono() async {
    try {
      final db = await LocalDatabase.instance.database;
      final rows = await db.query(
        'users',
        columns: ['phone', 'whatsapp'],
        where: 'id = ?',
        whereArgs: [TenantSession.instance.userId],
        limit: 1,
      );
      if (rows.isEmpty || !mounted || _telefono.text.isNotEmpty) return;
      final row = rows.first;
      final phone = [row['whatsapp'], row['phone']]
          .whereType<String>()
          .firstWhere((p) => p.trim().isNotEmpty, orElse: () => '');
      if (phone.isNotEmpty) _telefono.text = phone.trim();
    } catch (_) {
      // Sin perfil guardado: el campo queda vacío.
    }
  }

  @override
  void dispose() {
    _detalle.dispose();
    _otro.dispose();
    _telefono.dispose();
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
    if (!_puedeEnviar || tipo == null) return;
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
        otherTypeLabel: tipo == VulnerabilityType.otro ? _otro.text : null,
        peopleCount: _personas,
        hasInjured: _heridos,
        vulnerableGroups: [
          for (final g in VulnerableGroup.labels.keys)
            if (_grupos.contains(g)) g,
        ],
        contactPhone: _telefono.text,
      );
      if (mounted) {
        Navigator.of(context).pop(
          ubicacion.fromGps ? true : SosSheet.savedWithoutGps,
        );
      }
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
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
                  // "Otro": solo con esta opción se escribe qué pasa.
                  if (_tipo == VulnerabilityType.otro)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 4),
                      child: TextField(
                        inputFormatters: const [OffensiveWordsFormatter()],
                        key: SosSheet.otherFieldKey,
                        controller: _otro,
                        autofocus: true,
                        maxLength: VulnerabilityType.maxOtherLabel,
                        textCapitalization: TextCapitalization.sentences,
                        style: texto.bodyLarge,
                        decoration: InputDecoration(
                          labelText: '¿Qué está pasando?',
                          hintText: 'Ej: Cayó un poste con cables',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    alignment: Alignment.topCenter,
                    child: _tipo == null
                        ? const SizedBox(width: double.infinity)
                        : _detalles(context),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null) ...[
                  // Se anuncia al lector de pantalla: en una emergencia nadie
                  // debe creer que su pedido se envió si no fue así.
                  Semantics(
                    liveRegion: true,
                    child: Text(_error!, style: texto.bodyMedium?.copyWith(color: esquema.error)),
                  ),
                  const SizedBox(height: 8),
                ],
                FilledButton(
                  key: SosSheet.sendButtonKey,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    backgroundColor: AppPalette.emergencyPrimary,
                    foregroundColor: AppPalette.emergencyOnPrimary,
                  ),
                  onPressed: _puedeEnviar ? _enviar : null,
                  child: Text(
                    _enviando
                        ? 'Buscando tu ubicación y guardando…'
                        : 'Enviar pedido de ayuda',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Urgencia y datos que ayudan a decidir a quién atender primero.
  Widget _detalles(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    final esquema = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Urgencia', style: texto.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(minimumSize: const Size(48, 52)),
            segments: [
              for (final nivel in UrgencyLevel.labels.keys)
                ButtonSegment(value: nivel, label: Text(UrgencyLevel.labels[nivel]!)),
            ],
            selected: {_urgencia},
            onSelectionChanged: (v) => setState(() => _urgencia = v.first),
          ),
          const SizedBox(height: 20),
          Text('Datos que ayudan (opcional)', style: texto.titleMedium),
          Text(
            'Así los vecinos y la junta saben a quién ayudar primero.',
            style: texto.bodyMedium?.copyWith(color: esquema.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          // ¿Cuántas personas?
          Row(
            children: [
              Expanded(child: Text('¿Cuántas personas?', style: texto.bodyLarge)),
              IconButton.outlined(
                key: SosSheet.peopleMinusKey,
                tooltip: 'Menos personas',
                onPressed: _personas == null
                    ? null
                    : () => setState(
                        () => _personas = _personas! <= 1 ? null : _personas! - 1,
                      ),
                icon: const Icon(Icons.remove_rounded),
              ),
              SizedBox(
                width: 48,
                child: Text(
                  _personas?.toString() ?? '—',
                  textAlign: TextAlign.center,
                  style: texto.titleMedium,
                ),
              ),
              IconButton.outlined(
                key: SosSheet.peoplePlusKey,
                tooltip: 'Más personas',
                onPressed: (_personas ?? 0) >= 99
                    ? null
                    : () => setState(() => _personas = (_personas ?? 0) + 1),
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // ¿Hay heridos? (tocar de nuevo deja la respuesta en blanco)
          Row(
            children: [
              Expanded(child: Text('¿Hay heridos?', style: texto.bodyLarge)),
              for (final (valor, etiqueta) in const [(true, 'Sí'), (false, 'No')])
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: ChoiceChip(
                    key: ValueKey('sos_injured_$valor'),
                    label: Text(etiqueta),
                    selected: _heridos == valor,
                    onSelected: (_) =>
                        setState(() => _heridos = _heridos == valor ? null : valor),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text('¿Hay alguien que necesite más cuidado?', style: texto.bodyLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in VulnerableGroup.labels.entries)
                FilterChip(
                  key: ValueKey('sos_group_${entry.key}'),
                  label: Text(entry.value),
                  selected: _grupos.contains(entry.key),
                  onSelected: (on) => setState(
                    () => on ? _grupos.add(entry.key) : _grupos.remove(entry.key),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            key: SosSheet.phoneFieldKey,
            controller: _telefono,
            keyboardType: TextInputType.phone,
            maxLength: 20,
            style: texto.bodyLarge,
            decoration: InputDecoration(
              labelText: 'Teléfono para ubicarte',
              prefixIcon: const Icon(Icons.phone_rounded),
              counterText: '',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            inputFormatters: const [OffensiveWordsFormatter()],
            controller: _detalle,
            maxLength: 200,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            style: texto.bodyLarge,
            decoration: InputDecoration(
              labelText: 'Cuéntanos más (opcional)',
              hintText: 'Ej: Casa azul, 2do piso. Somos 4 y hay un bebé',
              alignLabelWithHint: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
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
      // TalkBack: sin esto el doble toque no hace nada (excludeSemantics
      // quita también la acción del botón de adentro).
      onTap: onTap,
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
                  Icon(icon, size: 28 * escalaIcono(context), color: frente),
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
