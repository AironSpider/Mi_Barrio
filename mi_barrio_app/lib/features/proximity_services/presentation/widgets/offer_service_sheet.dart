import 'package:flutter/material.dart';

import '../../../../core/barrio_context/tenant_session.dart';
import '../../../../core/database_sqlite/sqlite_database.dart';
import '../../data/datasources/services_sqlite_ds.dart';
import '../../data/models/service_model.dart';

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

/// Abre la hoja "Ofrecer servicio". Devuelve true si se publicó.
Future<bool> showOfferServiceSheet(
  BuildContext context, {
  String? tenantId,
  String? userId,
  ServicesSqliteDatasource? datasource,
  MerchantProfile profile = const MerchantProfile.none(),
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => OfferServiceSheet(
      tenantId: tenantId,
      userId: userId,
      datasource: datasource,
      profile: profile,
    ),
  ).then((published) => published ?? false);
}

/// Publicar un servicio en 3 clics: rubro → título → publicar.
/// Se guarda al instante en el teléfono (PENDING) aunque no haya internet.
class OfferServiceSheet extends StatefulWidget {
  const OfferServiceSheet({
    super.key,
    this.tenantId,
    this.userId,
    this.datasource,
    this.profile = const MerchantProfile.none(),
    this.lat,
    this.lng,
  });

  final String? tenantId;
  final String? userId;
  final ServicesSqliteDatasource? datasource;
  final MerchantProfile profile;

  /// Ubicación del servicio (por defecto, el centro del barrio de la sesión).
  final double? lat;
  final double? lng;

  static const titleKey = ValueKey('offer_service_title');
  static const publishKey = ValueKey('offer_service_publish');
  static const emergencySwitchKey = ValueKey('offer_service_emergency');

  @override
  State<OfferServiceSheet> createState() => _OfferServiceSheetState();
}

class _OfferServiceSheetState extends State<OfferServiceSheet> {
  static const _rubros = <(String, String, IconData)>[
    (ServiceCategory.gasfiteria, 'Gasfitería', Icons.plumbing_rounded),
    (ServiceCategory.electricidad, 'Electricidad', Icons.electrical_services_rounded),
    (ServiceCategory.carpinteria, 'Carpintería', Icons.carpenter_rounded),
    (ServiceCategory.cerrajeria, 'Cerrajería', Icons.key_rounded),
    (ServiceCategory.clases, 'Clases', Icons.school_rounded),
    (ServiceCategory.paseadorMascotas, 'Mascotas', Icons.pets_rounded),
    (ServiceCategory.soporteEmergencia, 'Soporte en emergencia', Icons.health_and_safety_rounded),
  ];

  final TextEditingController _title = TextEditingController();
  late final ServicesSqliteDatasource _datasource;
  String? _category;
  bool _emergency = false;
  bool _saving = false;
  String? _error;

  bool get _canPublish =>
      !_saving && _category != null && _title.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _datasource = widget.datasource ?? ServicesSqliteDatasource();
    _title.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _publish() async {
    if (!_canPublish) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final session = TenantSession.instance;
    try {
      await _datasource.insertService(
        tenantId: widget.tenantId ?? session.tenantId,
        providerUserId: widget.userId ?? session.userId,
        category: _category!,
        title: _title.text.trim(),
        lat: widget.lat ?? session.centerLat,
        lng: widget.lng ?? session.centerLng,
        isAvailableInEmergency: _emergency,
        publisherType: widget.profile.publisherType,
        publisherName: widget.profile.publisherName,
      );
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

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final texto = Theme.of(context).textTheme;
    final keyboard = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ofrecer un servicio', style: texto.titleLarge),
            const SizedBox(height: 4),
            Text(
              'Se guarda en tu teléfono y se envía cuando haya internet.',
              style: texto.bodyMedium,
            ),
            const SizedBox(height: 16),
            Text('¿Qué rubro es?', style: texto.titleMedium),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 2.4,
              children: [
                for (final (value, label, icon) in _rubros)
                  _RubroTile(
                    label: label,
                    icon: icon,
                    selected: _category == value,
                    onTap: () => setState(() => _category = value),
                  ),
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: _category == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            key: OfferServiceSheet.titleKey,
                            controller: _title,
                            autofocus: true,
                            maxLength: 80,
                            textCapitalization: TextCapitalization.sentences,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _publish(),
                            style: texto.bodyLarge,
                            decoration: InputDecoration(
                              labelText: 'Cuéntalo en una línea',
                              hintText: 'Ej: Gasfitero a domicilio',
                              counterText: '',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                          SwitchListTile(
                            key: OfferServiceSheet.emergencySwitchKey,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              'Disponible en emergencias',
                              style: texto.bodyLarge,
                            ),
                            value: _emergency,
                            onChanged: (value) =>
                                setState(() => _emergency = value),
                          ),
                        ],
                      ),
                    ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  style: texto.bodyMedium?.copyWith(color: esquema.error),
                ),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
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
                    : const Icon(Icons.check_rounded),
                label: const Text('Publicar ahora'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RubroTile extends StatelessWidget {
  const _RubroTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final texto = Theme.of(context).textTheme;
    final fondo = selected ? esquema.primary : esquema.primaryContainer;
    final contenido = selected ? esquema.onPrimary : esquema.onPrimaryContainer;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: fondo,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(icon, size: 28, color: contenido),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: texto.labelLarge?.copyWith(color: contenido),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
