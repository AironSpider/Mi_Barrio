import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../../core/barrio_context/emergency_mode_provider.dart';
import '../../../../core/barrio_context/tenant_session.dart';
import '../../../../core/ui_kit/emergency_switch_tile.dart';
import '../../../../core/ui_kit/location_map.dart';
import '../../../../core/ui_kit/photo_picker.dart';
import '../../../../core/ui_kit/safe_image.dart';
import '../../../emergency_support/presentation/providers/emergency_provider.dart';
import '../../data/datasources/solidarity_sqlite_ds.dart';
import '../../data/models/solidarity_post_model.dart';
import '../../../../core/moderation/content_filter.dart';

/// Abre "Pedir / Brindar apoyo" en pantalla completa (botón Publicar de la
/// pestaña Apoyo). Devuelve true si se publicó.
Future<bool> showApoyoScreen(
  BuildContext context, {
  SolidaritySqliteDatasource? datasource,
}) {
  return Navigator.of(context)
      .push<bool>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => ApoyoScreen(datasource: datasource),
        ),
      )
      .then((saved) => saved ?? false);
}

/// Formulario de apoyo (favor sin dinero): igual que el de servicios pero sin
/// precio. Pedir / Brindar, tipo, título, descripción, fotos, ubicación y el
/// interruptor de emergencia. Se guarda en el teléfono aunque no haya internet.
class ApoyoScreen extends StatefulWidget {
  const ApoyoScreen({super.key, this.datasource, this.lat, this.lng});

  final SolidaritySqliteDatasource? datasource;

  /// Ubicación inicial (por defecto: GPS o, si no hay, el centro del barrio).
  final double? lat;
  final double? lng;

  static const flowKey = ValueKey('apoyo_flow');
  static const titleKey = ValueKey('apoyo_title');
  static const descriptionKey = ValueKey('apoyo_description');
  static const publishKey = ValueKey('apoyo_publish');
  static const emergencySwitchKey = ValueKey('apoyo_emergency');
  static const addPhotoKey = ValueKey('apoyo_add_photo');

  static ValueKey<String> typeKey(String modality) =>
      ValueKey('apoyo_type_$modality');

  /// Ícono de cada tipo de apoyo.
  static const icons = <String, IconData>{
    SolidarityModality.prestamoHerramienta: Icons.hardware_rounded,
    SolidarityModality.intercambioHabilidad: Icons.school_rounded,
    SolidarityModality.donacionMaterial: Icons.inventory_2_rounded,
    SolidarityModality.ayudaTemporal: Icons.volunteer_activism_rounded,
    SolidarityModality.movilidadSolidaria: Icons.directions_car_rounded,
    SolidarityModality.alimentos: Icons.restaurant_rounded,
    SolidarityModality.ropa: Icons.checkroom_rounded,
    SolidarityModality.mascotas: Icons.pets_rounded,
    SolidarityModality.apoyoEscolar: Icons.menu_book_rounded,
    SolidarityModality.recursoCritico: Icons.emergency_rounded,
    SolidarityModality.otro: Icons.more_horiz_rounded,
  };

  @override
  State<ApoyoScreen> createState() => _ApoyoScreenState();
}

class _ApoyoScreenState extends State<ApoyoScreen> {
  late final SolidaritySqliteDatasource _datasource =
      widget.datasource ?? SolidaritySqliteDatasource();
  final _title = TextEditingController();
  final _description = TextEditingController();
  String _flow = SolidarityFlowType.solicitoAyuda;
  String? _type;
  // En modo emergencia viene encendido.
  bool _emergency = EmergencyModeProvider.instance.isActive.value;
  late double _lat;
  late double _lng;
  int _mapVersion = 0;
  bool _locating = false;
  String? _locationNote;
  List<String> _photos = [];
  bool _saving = false;
  String? _error;

  bool get _isNeed => _flow == SolidarityFlowType.solicitoAyuda;

  /// "Otro" no crea una categoría nueva: la descripción cuenta de qué se trata.
  bool get _needsDescription =>
      _type == SolidarityModality.otro && _description.text.trim().length < 3;

  bool get _canPublish =>
      !_saving &&
      _type != null &&
      _title.text.trim().isNotEmpty &&
      !_needsDescription;

  List<String> get _types => [
    for (final type in SolidarityModality.labels.keys)
      // "Recurso crítico" (agua, comida, medicina) solo en emergencia.
      if (type != SolidarityModality.recursoCritico ||
          EmergencyModeProvider.instance.isActive.value)
        type,
  ];

  @override
  void initState() {
    super.initState();
    final session = TenantSession.instance;
    _lat = widget.lat ?? session.centerLat;
    _lng = widget.lng ?? session.centerLng;
    _title.addListener(() => setState(() {}));
    _description.addListener(() => setState(() {}));
    if (widget.lat == null) unawaited(_useGps(silent: true));
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _useGps({bool silent = false}) async {
    setState(() => _locating = true);
    final loc = await HelpLocator.resolve();
    if (!mounted) return;
    setState(() {
      _locating = false;
      if (loc.fromGps) {
        _lat = loc.lat;
        _lng = loc.lng;
        _mapVersion++;
        _locationNote = null;
      } else if (!silent) {
        _locationNote =
            'No pudimos usar el GPS. Toca el mapa para marcar el lugar.';
      }
    });
  }

  Future<void> _addPhoto() async {
    if (_photos.length >= SolidaritySqliteDatasource.maxPhotos) return;
    try {
      final b64 = await pickPhotoB64(
        context,
        maxB64Length: SolidaritySqliteDatasource.maxPhotoB64Length,
      );
      if (b64 == null || !mounted) return;
      setState(() {
        _photos = [..._photos, b64];
        _error = null;
      });
    } on StateError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'No se pudo abrir la cámara o la galería.');
      }
    }
  }

  Future<void> _publish() async {
    if (!_canPublish) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final session = TenantSession.instance;
    try {
      await _datasource.publishInThreeClicks(
        tenantId: session.tenantId,
        authorUserId: session.userId,
        modality: _type!,
        title: _title.text,
        description: _description.text,
        flowType: _flow,
        isEmergencyContext: _emergency,
        photos: _photos,
        lat: _lat,
        lng: _lng,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ArgumentError catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Revisa los datos: ${e.message}';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'No se pudo guardar. Intenta de nuevo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    final esquema = Theme.of(context).colorScheme;

    Widget section(String title, {String? hint}) => Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: texto.titleMedium),
          if (hint != null)
            Text(
              hint,
              style: texto.bodyMedium?.copyWith(
                color: esquema.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(title: Text(_isNeed ? 'Pedir apoyo' : 'Brindar apoyo')),
      // "Publicar" siempre a la vista: no hace falta bajar (regla de 3 clics).
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            key: ApoyoScreen.publishKey,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
            ),
            onPressed: _canPublish ? _publish : null,
            icon: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : const Icon(Icons.check_rounded),
            label: Text(_isNeed ? 'Publicar pedido' : 'Publicar apoyo'),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            'Favores sin dinero entre vecinos. Se guarda en tu teléfono y se '
            'publica cuando haya internet.',
            style: texto.bodyMedium?.copyWith(color: esquema.onSurfaceVariant),
          ),
          section('¿Pides o brindas?'),
          SegmentedButton<String>(
            key: ApoyoScreen.flowKey,
            style: SegmentedButton.styleFrom(minimumSize: const Size(48, 52)),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: SolidarityFlowType.solicitoAyuda,
                label: Text('Pedir'),
                icon: Icon(Icons.back_hand_rounded),
              ),
              ButtonSegment(
                value: SolidarityFlowType.ofrezcoAyuda,
                label: Text('Brindar'),
                icon: Icon(Icons.favorite_rounded),
              ),
            ],
            selected: {_flow},
            onSelectionChanged: (v) => setState(() => _flow = v.first),
          ),
          section('¿Qué tipo de apoyo?'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final type in _types)
                ChoiceChip(
                  key: ApoyoScreen.typeKey(type),
                  avatar: Icon(ApoyoScreen.icons[type], size: 18),
                  label: Text(SolidarityModality.labels[type]!),
                  selected: _type == type,
                  onSelected: (_) => setState(() => _type = type),
                ),
            ],
          ),
          section(_isNeed ? '¿Qué necesitas?' : '¿Qué brindas?'),
          TextField(
            inputFormatters: const [OffensiveWordsFormatter()],
            key: ApoyoScreen.titleKey,
            controller: _title,
            maxLength: 80,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Título',
              hintText: _isNeed
                  ? 'Ej: Necesito una escalera por un día'
                  : 'Ej: Presto mi taladro',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            inputFormatters: const [OffensiveWordsFormatter()],
            key: ApoyoScreen.descriptionKey,
            controller: _description,
            maxLength: 600,
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: _type == SolidarityModality.otro
                  ? 'Descripción (cuéntanos de qué se trata)'
                  : 'Descripción (opcional)',
              hintText: 'Cuándo, por cuánto tiempo, detalles que ayuden…',
              alignLabelWithHint: true,
              border: const OutlineInputBorder(),
              errorText:
                  _type == SolidarityModality.otro &&
                      _description.text.isNotEmpty &&
                      _needsDescription
                  ? 'Escribe un poco más'
                  : null,
            ),
          ),
          section(
            'Fotos (${_photos.length}/${SolidaritySqliteDatasource.maxPhotos})',
            hint:
                'Opcional. Una foto ayuda a entender qué necesitas o brindas.',
          ),
          SizedBox(
            height: 96,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final (i, photo) in _photos.indexed)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: SafeMemoryImage(
                            base64Decode(photo),
                            width: 96,
                            height: 96,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          right: 2,
                          top: 2,
                          child: IconButton.filledTonal(
                            tooltip: 'Quitar foto ${i + 1}',
                            iconSize: 18,
                            visualDensity: VisualDensity.compact,
                            onPressed: () => setState(
                              () => _photos = [..._photos]..removeAt(i),
                            ),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_photos.length < SolidaritySqliteDatasource.maxPhotos)
                  Semantics(
                    button: true,
                    label: 'Agregar foto',
                    // TalkBack: sin esto el doble toque no hace nada (excludeSemantics
                    // quita también la acción del botón de adentro).
                    onTap: _addPhoto,
                    excludeSemantics: true,
                    child: InkWell(
                      key: ApoyoScreen.addPhotoKey,
                      onTap: _addPhoto,
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: esquema.outline),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.add_a_photo_rounded,
                              color: esquema.primary,
                            ),
                            const SizedBox(height: 4),
                            Text('Agregar', style: texto.labelMedium),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          section('¿Dónde?', hint: 'Toca el mapa para mover el punto.'),
          LocationMap(
            key: ValueKey('apoyo_map_$_mapVersion'),
            lat: _lat,
            lng: _lng,
            label: 'Mapa: dónde es el apoyo. Tócalo para moverlo.',
            icon: _type == null
                ? Icons.volunteer_activism_rounded
                : ApoyoScreen.icons[_type]!,
            onTapPoint: (lat, lng) => setState(() {
              _lat = lat;
              _lng = lng;
            }),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            onPressed: _locating ? null : () => _useGps(),
            icon: _locating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location_rounded),
            label: const Text('Usar mi ubicación actual'),
          ),
          if (_locationNote != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_locationNote!, style: texto.bodyMedium),
            ),
          const SizedBox(height: 16),
          EmergencySwitchTile(
            key: ApoyoScreen.emergencySwitchKey,
            value: _emergency,
            isNeed: _isNeed,
            onChanged: (v) => setState(() => _emergency = v),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                style: texto.bodyMedium?.copyWith(color: esquema.error),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
