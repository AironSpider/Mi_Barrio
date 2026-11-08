import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../../core/barrio_context/tenant_session.dart';
import '../../../../core/database_sqlite/sqlite_database.dart';
import '../../../../core/ui_kit/location_map.dart';
import '../../../../core/ui_kit/photo_picker.dart';
import '../../../emergency_support/presentation/providers/emergency_provider.dart';
import '../../data/datasources/services_sqlite_ds.dart';
import '../../data/models/service_model.dart';
import 'service_category_ui.dart';
import '../../../../core/ui_kit/safe_image.dart';

/// Lo que la app necesita saber del vecino para ofrecer un servicio.
class MerchantProfile {
  const MerchantProfile({
    required this.isMerchant,
    this.publisherType,
    this.publisherName,
  });

  const MerchantProfile.none() : this(isMerchant: false);

  final bool isMerchant;
  final String? publisherType;
  final String? publisherName;
}

/// Lee el rol y el perfil de publicador del vecino desde su perfil local
/// (tabla `users`). Si no hay perfil guardado, no es comerciante.
Future<MerchantProfile> loadMerchantProfile(
  String userId, {
  String? tenantId,
}) async {
  try {
    final db = await LocalDatabase.instance.database;
    final rows = await db.query(
      'users',
      columns: ['role', 'publisher_type', 'publisher_name'],
      where: 'id = ? AND tenant_id = ? AND is_deleted = 0',
      whereArgs: [userId, tenantId ?? TenantSession.instance.tenantId],
      limit: 1,
    );
    if (rows.isEmpty) return const MerchantProfile.none();
    final row = rows.first;
    return MerchantProfile(
      isMerchant: row['role'] == 'COMERCIANTE',
      publisherType: row['publisher_type'] as String?,
      publisherName: row['publisher_name'] as String?,
    );
  } catch (_) {
    return const MerchantProfile.none();
  }
}

/// Abre "Ofrecer servicio" (o "Editar servicio" si viene [existing]) en
/// pantalla completa. Devuelve true si se guardó.
Future<bool> showOfferServiceSheet(
  BuildContext context, {
  String? tenantId,
  String? userId,
  ServicesSqliteDatasource? datasource,
  MerchantProfile profile = const MerchantProfile.none(),
  LocalServiceModel? existing,
}) {
  return Navigator.of(context)
      .push<bool>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => OfferServiceSheet(
            tenantId: tenantId,
            userId: userId,
            datasource: datasource,
            profile: profile,
            existing: existing,
          ),
        ),
      )
      .then((saved) => saved ?? false);
}

/// Formulario de servicio: rubro, qué ofreces, precio, fotos, dónde atiendes
/// y si atiendes emergencias. Para crear o editar ([existing]).
/// Se guarda al instante en el teléfono (PENDING) aunque no haya internet.
class OfferServiceSheet extends StatefulWidget {
  const OfferServiceSheet({
    super.key,
    this.tenantId,
    this.userId,
    this.datasource,
    this.profile = const MerchantProfile.none(),
    this.existing,
    this.lat,
    this.lng,
  });

  final String? tenantId;
  final String? userId;
  final ServicesSqliteDatasource? datasource;
  final MerchantProfile profile;

  /// Servicio a editar (null = nuevo).
  final LocalServiceModel? existing;

  /// Ubicación inicial (por defecto: GPS o, si no hay, el centro del barrio).
  final double? lat;
  final double? lng;

  static const titleKey = ValueKey('offer_service_title');
  static const descriptionKey = ValueKey('offer_service_description');
  static const priceKey = ValueKey('offer_service_price');
  static const publishKey = ValueKey('offer_service_publish');
  static const retireKey = ValueKey('offer_service_retire');
  static const emergencySwitchKey = ValueKey('offer_service_emergency');
  static const addPhotoKey = ValueKey('offer_service_add_photo');
  static const gpsKey = ValueKey('offer_service_gps');

  @override
  State<OfferServiceSheet> createState() => _OfferServiceSheetState();
}

class _OfferServiceSheetState extends State<OfferServiceSheet> {
  late final ServicesSqliteDatasource _datasource =
      widget.datasource ?? ServicesSqliteDatasource();
  late final LocalServiceModel? _existing = widget.existing;
  late final TextEditingController _title = TextEditingController(
    text: _existing?.title,
  );
  late final TextEditingController _description = TextEditingController(
    text: _existing?.description,
  );
  late final TextEditingController _price = TextEditingController(
    text: _existing?.priceText,
  );
  late String? _category = _existing?.category;
  late bool _emergency = _existing?.isAvailableInEmergency ?? false;
  late double _lat;
  late double _lng;
  int _mapVersion = 0;
  bool _locating = false;
  String? _locationNote;

  List<String> _photos = [];
  bool _photosChanged = false;
  bool _saving = false;
  String? _error;

  bool get _isEdit => _existing != null;
  bool get _canPublish =>
      !_saving && _category != null && _title.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    final session = TenantSession.instance;
    _lat = widget.lat ?? _existing?.lat ?? session.centerLat;
    _lng = widget.lng ?? _existing?.lng ?? session.centerLng;
    _title.addListener(() => setState(() {}));
    if (_isEdit) {
      _datasource.localPhotos(_existing!.id).then((p) {
        if (mounted) setState(() => _photos = [...p]);
      });
    } else if (widget.lat == null) {
      unawaited(_useGps(silent: true));
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _price.dispose();
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
            'No pudimos usar el GPS. Toca el mapa para marcar dónde atiendes.';
      }
    });
  }

  Future<void> _addPhoto() async {
    if (_photos.length >= LocalServiceModel.maxPhotos) return;
    try {
      final b64 = await pickPhotoB64(
        context,
        maxB64Length: ServicesSqliteDatasource.maxPhotoB64Length,
      );
      if (b64 == null || !mounted) return;
      setState(() {
        _photos = [..._photos, b64];
        _photosChanged = true;
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
      final existing = _existing;
      if (existing != null) {
        await _datasource.updateService(
          current: existing,
          providerUserId: widget.userId ?? session.userId,
          category: _category!,
          title: _title.text,
          description: _description.text,
          lat: _lat,
          lng: _lng,
          isAvailableInEmergency: _emergency,
          priceText: _price.text,
          photos: _photosChanged ? _photos : null,
        );
      } else {
        await _datasource.insertService(
          tenantId: widget.tenantId ?? session.tenantId,
          providerUserId: widget.userId ?? session.userId,
          category: _category!,
          title: _title.text.trim(),
          description: _description.text,
          lat: _lat,
          lng: _lng,
          isAvailableInEmergency: _emergency,
          publisherType: widget.profile.publisherType,
          publisherName: widget.profile.publisherName,
          priceText: _price.text,
          photos: _photos,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ArgumentError catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Revisa los datos: ${error.message}';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'No se pudo guardar. Intenta de nuevo.';
      });
    }
  }

  Future<void> _retire() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Retirar este servicio?'),
        content: const Text(
          'Tus vecinos ya no lo verán en el directorio. Sus reseñas se conservan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Retirar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _datasource.retireService(
      _existing!,
      widget.userId ?? TenantSession.instance.userId,
    );
    if (mounted) Navigator.of(context).pop(true);
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
      appBar: AppBar(
        title: Text(_isEdit ? 'Editar servicio' : 'Ofrecer un servicio'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            'Se guarda en tu teléfono y se publica cuando haya internet.',
            style: texto.bodyMedium?.copyWith(color: esquema.onSurfaceVariant),
          ),
          section('¿Qué rubro es?'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final cat in ServiceCategory.labels.keys)
                ChoiceChip(
                  key: ValueKey('offer_category_$cat'),
                  avatar: Icon(ServiceCategoryUi.icon(cat), size: 18),
                  label: Text(ServiceCategoryUi.shortLabel(cat)),
                  selected: _category == cat,
                  onSelected: (_) => setState(() => _category = cat),
                ),
            ],
          ),
          section('¿Qué ofreces?'),
          TextField(
            key: OfferServiceSheet.titleKey,
            controller: _title,
            maxLength: 80,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Título',
              hintText: 'Ej: Gasfitero a domicilio',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: OfferServiceSheet.descriptionKey,
            controller: _description,
            maxLength: 600,
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Descripción (opcional)',
              hintText: 'Qué haces, horarios, experiencia…',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          ),
          section(
            '¿Cuánto cuesta?',
            hint: 'Opcional. Ej: "S/ 30 la visita" o "A tratar".',
          ),
          TextField(
            key: OfferServiceSheet.priceKey,
            controller: _price,
            maxLength: 60,
            decoration: const InputDecoration(
              labelText: 'Precio',
              prefixIcon: Icon(Icons.sell_outlined),
              hintText: 'S/ 30 la visita',
              border: OutlineInputBorder(),
            ),
          ),
          Wrap(
            spacing: 8,
            children: [
              for (final quick in const [
                'A tratar',
                'Desde S/ 20',
                'Primera visita gratis',
              ])
                ActionChip(
                  label: Text(quick),
                  onPressed: () => setState(() => _price.text = quick),
                ),
            ],
          ),
          section(
            'Fotos (${_photos.length}/${LocalServiceModel.maxPhotos})',
            hint: 'Muestra tus trabajos: generan más confianza.',
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
                            onPressed: () => setState(() {
                              _photos = [..._photos]..removeAt(i);
                              _photosChanged = true;
                            }),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_photos.length < LocalServiceModel.maxPhotos)
                  Semantics(
                    button: true,
                    label: 'Agregar foto',
                    excludeSemantics: true,
                    child: InkWell(
                      key: OfferServiceSheet.addPhotoKey,
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
          section(
            '¿Dónde atiendes?',
            hint: 'Toca el mapa para mover el punto.',
          ),
          LocationMap(
            key: ValueKey('offer_map_$_mapVersion'),
            lat: _lat,
            lng: _lng,
            label: 'Mapa: ubicación de tu servicio. Tócalo para moverla.',
            icon: _category == null
                ? Icons.storefront_rounded
                : ServiceCategoryUi.icon(_category!),
            onTapPoint: (lat, lng) => setState(() {
              _lat = lat;
              _lng = lng;
            }),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: OfferServiceSheet.gpsKey,
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
          Card(
            child: SwitchListTile(
              key: OfferServiceSheet.emergencySwitchKey,
              value: _emergency,
              onChanged: (v) => setState(() => _emergency = v),
              secondary: const Icon(Icons.health_and_safety_rounded),
              title: const Text('Atiendo en emergencias'),
              subtitle: const Text(
                'Apareces primero cuando el barrio está en emergencia.',
              ),
            ),
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
          const SizedBox(height: 20),
          FilledButton.icon(
            key: OfferServiceSheet.publishKey,
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
                : Icon(_isEdit ? Icons.save_rounded : Icons.check_rounded),
            label: Text(_isEdit ? 'Guardar cambios' : 'Publicar servicio'),
          ),
          if (_isEdit) ...[
            const SizedBox(height: 10),
            TextButton.icon(
              key: OfferServiceSheet.retireKey,
              style: TextButton.styleFrom(
                foregroundColor: esquema.error,
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: _saving ? null : _retire,
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Retirar servicio'),
            ),
          ],
        ],
      ),
    );
  }
}
