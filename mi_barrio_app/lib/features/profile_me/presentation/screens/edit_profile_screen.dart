import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/barrio_context/tenant_session.dart';
import '../../../../core/ui_kit/app_select_field.dart';
import '../../../proximity_services/data/models/service_model.dart';
import '../../data/profile_local_storage.dart';
import '../../data/user_profile_model.dart';

/// "Mi Perfil y Cuenta": datos personales, redes de contacto y perfil de publicador.
///
/// Guarda en SQLite con `PENDING` y encola el cambio; el SyncWorker lo sube cuando
/// hay internet. "Guardar cambios" se habilita solo cuando algo cambió.
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key, this.storage});

  final ProfileLocalStorage? storage;

  static const saveButtonKey = ValueKey('edit_profile_save');

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final ProfileLocalStorage _storage;
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _whatsapp = TextEditingController();
  final _facebook = TextEditingController();
  final _instagram = TextEditingController();
  final _businessName = TextEditingController();
  String? _publisherType;
  String? _publisherCategory;

  UserProfileModel? _profile;
  Map<String, String?> _saved = const {};
  bool _loading = true;
  bool _saving = false;
  String? _error;

  List<TextEditingController> get _controllers =>
      [_name, _phone, _address, _whatsapp, _facebook, _instagram, _businessName];

  @override
  void initState() {
    super.initState();
    _storage = widget.storage ?? ProfileLocalStorage();
    for (final c in _controllers) {
      c.addListener(_onChanged);
    }
    unawaited(_load());
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _onChanged() => setState(() {});

  Map<String, String?> get _current => {
        'name': _name.text.trim(),
        'phone': _phone.text.trim(),
        'address': _address.text.trim(),
        'whatsapp': _whatsapp.text.trim(),
        'facebook': _facebook.text.trim(),
        'instagram': _instagram.text.trim(),
        'business': _hasBusiness ? _businessName.text.trim() : '',
        'type': _publisherType,
        'category': _publisherCategory,
      };

  bool get _hasBusiness => _publisherType != null && _publisherType != 'PERSONA_NATURAL';

  bool get _isDirty {
    final current = _current;
    return current.keys.any((k) => (current[k] ?? '') != (_saved[k] ?? ''));
  }

  Future<void> _load() async {
    try {
      final profile = await _storage.getProfile(TenantSession.instance.userId);
      if (!mounted) return;
      _profile = profile;
      _name.text = profile?.fullName ?? '';
      _phone.text = profile?.phone ?? '';
      _address.text = profile?.addressReference ?? '';
      _whatsapp.text = profile?.whatsapp ?? '';
      _facebook.text = profile?.facebookUrl ?? '';
      _instagram.text = profile?.instagramUrl ?? '';
      _businessName.text = profile?.publisherName ?? '';
      _publisherType = profile?.publisherType;
      _publisherCategory = profile?.publisherCategory;
      _saved = _current;
    } catch (_) {
      _error = 'No pudimos abrir tu perfil. Intenta de nuevo.';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (_saving || !_isDirty) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final session = TenantSession.instance;
    try {
      final profile = await _storage.saveProfile(
        userId: session.userId,
        tenantId: session.tenantId,
        fullName: _name.text,
        phone: _phone.text,
        addressReference: _address.text,
        homeLat: _profile?.homeLat ?? session.centerLat,
        homeLng: _profile?.homeLng ?? session.centerLng,
        email: _profile?.email,
        whatsapp: _whatsapp.text,
        facebookUrl: _facebook.text,
        instagramUrl: _instagram.text,
        publisherType: _publisherType,
        publisherCategory: _publisherCategory,
        publisherName: _businessName.text,
      );
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _saved = _current;
      });
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('Guardado en tu teléfono. Lo enviaremos cuando haya internet.'),
        ));
    } on ArgumentError catch (e) {
      if (mounted) setState(() => _error = _friendly(e.name));
    } catch (_) {
      if (mounted) setState(() => _error = 'No pudimos guardar. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Mensaje humano según el campo que falló (sin detalles técnicos).
  static String _friendly(String? field) => switch (field) {
        'fullName' => 'Escribe tu nombre y apellido.',
        'phone' => 'El teléfono debe tener solo números (6 a 20), con + opcional.',
        'whatsapp' => 'El WhatsApp debe tener solo números (6 a 20), con + opcional.',
        'facebookUrl' => 'El enlace de Facebook debe empezar con https://',
        'instagramUrl' => 'El enlace de Instagram debe empezar con https://',
        _ => 'Revisa los datos e intenta de nuevo.',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Mi perfil y cuenta')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                _section(theme, 'Datos personales'),
                _field(_name, 'Nombre y apellido', capitalization: TextCapitalization.words),
                _field(_phone, 'Teléfono (opcional)', keyboard: TextInputType.phone),
                _field(_address, 'Referencia de domicilio (opcional)',
                    capitalization: TextCapitalization.sentences),
                _section(theme, 'Redes y contacto',
                    hint: 'Se usan para que tus vecinos te contacten cuando publiques un servicio.'),
                _field(_whatsapp, 'WhatsApp (opcional)', keyboard: TextInputType.phone,
                    icon: Icons.chat_rounded),
                _field(_facebook, 'Facebook (https://…)', keyboard: TextInputType.url,
                    icon: Icons.link_rounded),
                _field(_instagram, 'Instagram (https://…)', keyboard: TextInputType.url,
                    icon: Icons.photo_camera_rounded),
                _section(theme, 'Perfil de publicador',
                    hint: 'Opcional. Aparece en los servicios que ofreces.'),
                AppSelectField<String>(
                  label: 'Tipo',
                  allowClear: true,
                  value: _publisherType,
                  options: [
                    for (final e in PublisherType.labels.entries)
                      AppSelectOption(value: e.key, label: e.value),
                  ],
                  onChanged: (v) => setState(() => _publisherType = v),
                ),
                const SizedBox(height: 12),
                AppSelectField<String>(
                  label: 'Rubro',
                  allowClear: true,
                  value: _publisherCategory,
                  options: [
                    for (final e in ServiceCategory.labels.entries)
                      AppSelectOption(value: e.key, label: e.value),
                  ],
                  onChanged: (v) => setState(() => _publisherCategory = v),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  child: _hasBusiness
                      ? Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: _field(_businessName, 'Nombre de tu negocio (opcional)',
                              capitalization: TextCapitalization.words, bottom: 0),
                        )
                      : const SizedBox(width: double.infinity),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error)),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  key: EditProfileScreen.saveButtonKey,
                  onPressed: _isDirty && !_saving ? _save : null,
                  child: Text(_saving ? 'Guardando…' : 'Guardar cambios'),
                ),
              ],
            ),
    );
  }

  Widget _section(ThemeData theme, String title, {String? hint}) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            if (hint != null) ...[
              const SizedBox(height: 4),
              Text(hint, style: theme.textTheme.bodyMedium),
            ],
          ],
        ),
      );

  Widget _field(
    TextEditingController controller,
    String label, {
    TextInputType? keyboard,
    TextCapitalization capitalization = TextCapitalization.none,
    IconData? icon,
    double bottom = 12,
  }) =>
      Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: TextField(
          controller: controller,
          keyboardType: keyboard,
          textCapitalization: capitalization,
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: icon == null ? null : Icon(icon),
            border: const OutlineInputBorder(),
          ),
        ),
      );
}
