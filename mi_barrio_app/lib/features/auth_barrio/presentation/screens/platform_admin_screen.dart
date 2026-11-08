import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/auth/auth_session_store.dart';
import '../../../../core/location/gps_service.dart';
import '../../data/datasources/auth_remote_datasource.dart';
import '../../domain/entities/user_entity.dart';
import '../providers/auth_provider.dart';

/// Trae los barrios de la plataforma (lo inyectan los tests).
typedef NeighborhoodsLoader = Future<List<NeighborhoodSummary>> Function();

class PlatformAdminScreen extends ConsumerStatefulWidget {
  const PlatformAdminScreen({
    super.key,
    required this.user,
    this.gps,
    this.loadNeighborhoods,
  });

  final UserEntity user;

  /// Por defecto, `GET /api/v1/platform/neighborhoods` con la sesión actual.
  final NeighborhoodsLoader? loadNeighborhoods;

  /// Para "Usar mi ubicación" (los tests pasan uno falso).
  final GpsService? gps;

  static const newModeKey = ValueKey('platform_mode_new');
  static const existingModeKey = ValueKey('platform_mode_existing');
  static const useLocationKey = ValueKey('platform_use_location');
  static const submitKey = ValueKey('platform_submit');
  static ValueKey<String> neighborhoodKey(String id) =>
      ValueKey('platform_neighborhood_$id');

  @override
  ConsumerState<PlatformAdminScreen> createState() =>
      _PlatformAdminScreenState();
}

class _PlatformAdminScreenState extends ConsumerState<PlatformAdminScreen> {
  final _formKey = GlobalKey<FormState>();
  final _neighborhood = TextEditingController();
  final _existingJoinCode = TextEditingController();
  final _adminName = TextEditingController();
  final _adminEmail = TextEditingController();
  final _adminPassword = TextEditingController();
  final _latitude = TextEditingController();
  final _longitude = TextEditingController();
  NeighborhoodProvisionEntity? _created;
  bool _sending = false;
  bool _locating = false;
  bool _obscurePassword = true;
  String? _locationError;

  /// true = asignar administrador a un barrio que ya existe (por su código).
  bool _existing = false;
  bool _lastWasExisting = false;

  // Barrios reales de la plataforma (desde el servidor).
  List<NeighborhoodSummary>? _neighborhoods;
  String? _listError;
  bool _loadingList = false;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadNeighborhoods();
  }

  Future<void> _loadNeighborhoods() async {
    setState(() {
      _loadingList = true;
      _listError = null;
    });
    try {
      final loader =
          widget.loadNeighborhoods ??
          () => AuthRemoteDatasource().listNeighborhoods(
            AuthSessionStore.instance.token ?? '',
          );
      final list = await loader();
      if (!mounted) return;
      setState(() => _neighborhoods = list);
    } catch (error) {
      if (!mounted) return;
      setState(() => _listError = 'No se pudieron cargar los barrios: $error');
    } finally {
      if (mounted) setState(() => _loadingList = false);
    }
  }

  /// "Asignar administrador" en un barrio sin junta: llena el formulario.
  void _assignAdminTo(NeighborhoodSummary n) {
    setState(() {
      _existing = true;
      _existingJoinCode.text = n.inviteCode;
    });
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    _neighborhood.dispose();
    _existingJoinCode.dispose();
    _adminName.dispose();
    _adminEmail.dispose();
    _adminPassword.dispose();
    _latitude.dispose();
    _longitude.dispose();
    super.dispose();
  }

  Future<void> _useMyLocation() async {
    setState(() {
      _locating = true;
      _locationError = null;
    });
    try {
      final c = await (widget.gps ?? GpsService()).getCurrentCoordinates(
        timeLimit: const Duration(seconds: 10),
      );
      _latitude.text = c.latitude.toStringAsFixed(6);
      _longitude.text = c.longitude.toStringAsFixed(6);
    } catch (e) {
      _locationError = e is GpsException
          ? '$e Escribe las coordenadas a mano.'
          : 'No se pudo obtener tu ubicación. Escribe las coordenadas a mano.';
    }
    if (mounted) setState(() => _locating = false);
  }

  Future<void> _createNeighborhood() async {
    if (!_formKey.currentState!.validate() || _sending) return;
    setState(() {
      _sending = true;
      _created = null;
      _lastWasExisting = _existing;
    });
    final created = await ref
        .read(authProvider.notifier)
        .createNeighborhood(
          neighborhoodName: _existing ? '' : _neighborhood.text,
          existingJoinCode: _existing ? _existingJoinCode.text : null,
          adminFullName: _adminName.text,
          adminEmail: _adminEmail.text,
          adminPassword: _adminPassword.text,
          centerLat: double.tryParse(_latitude.text.trim()) ?? 0,
          centerLng: double.tryParse(_longitude.text.trim()) ?? 0,
        );
    if (mounted) {
      setState(() {
        _created = created;
        _sending = false;
      });
      if (created != null) unawaited(_loadNeighborhoods());
    }
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Campo obligatorio' : null;

  String? _coordinate(
    String? value, {
    required double min,
    required double max,
  }) {
    if (_existing) return null;
    final number = double.tryParse(value?.trim() ?? '');
    if (number == null || number < min || number > max) {
      return 'Ingresa un valor entre $min y $max';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final theme = Theme.of(context);
    Widget section(String title, IconData icon) => Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
        ],
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Administración de Mi Barrio'),
        actions: [
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: () => ref.read(authProvider.notifier).logout(),
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: ListView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        children: [
          Text(
            'Hola, ${widget.user.fullName}',
            style: theme.textTheme.headlineSmall,
          ),
          const SizedBox(height: 4),
          Text(
            'Da de alta un barrio con su administrador (la junta vecinal), '
            'o asigna un administrador a un barrio que ya existe.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          _NeighborhoodsSection(
            neighborhoods: _neighborhoods,
            loading: _loadingList,
            error: _listError,
            onRefresh: _loadNeighborhoods,
            onAssignAdmin: _assignAdminTo,
          ),
          const SizedBox(height: 24),
          Text('Dar de alta', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(minimumSize: const Size(48, 52)),
            segments: const [
              ButtonSegment(
                value: false,
                label: Text(
                  'Barrio nuevo',
                  key: PlatformAdminScreen.newModeKey,
                ),
                icon: Icon(Icons.add_home_work_rounded),
              ),
              ButtonSegment(
                value: true,
                label: Text(
                  'Barrio existente',
                  key: PlatformAdminScreen.existingModeKey,
                ),
                icon: Icon(Icons.vpn_key_rounded),
              ),
            ],
            selected: {_existing},
            onSelectionChanged: _sending
                ? null
                : (v) => setState(() => _existing = v.first),
          ),
          const SizedBox(height: 8),
          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                section('1. El barrio', Icons.location_city_rounded),
                if (_existing)
                  TextFormField(
                    controller: _existingJoinCode,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Código del barrio',
                      hintText: 'Ej: BARRIO-01',
                      helperText:
                          'El código de invitación que ya tiene ese barrio.',
                      prefixIcon: Icon(Icons.vpn_key_outlined),
                      border: OutlineInputBorder(),
                    ),
                    validator: _required,
                  )
                else ...[
                  TextFormField(
                    controller: _neighborhood,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Nombre del barrio',
                      hintText: 'Ej: Junta Vecinal Los Algarrobos',
                      prefixIcon: Icon(Icons.location_city_outlined),
                      border: OutlineInputBorder(),
                    ),
                    validator: _required,
                  ),
                  const SizedBox(height: 16),
                  Text('Centro del barrio', style: theme.textTheme.titleSmall),
                  Text(
                    'Se usa para ordenar por cercanía y centrar el mapa. Si estás '
                    'en el barrio, usa tu ubicación.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    key: PlatformAdminScreen.useLocationKey,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    onPressed: _locating || _sending ? null : _useMyLocation,
                    icon: _locating
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location_rounded),
                    label: const Text('Usar mi ubicación'),
                  ),
                  if (_locationError != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      _locationError!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _latitude,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Latitud',
                            hintText: '-5.1945',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) =>
                              _coordinate(value, min: -90, max: 90),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _longitude,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Longitud',
                            hintText: '-80.6328',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) =>
                              _coordinate(value, min: -180, max: 180),
                        ),
                      ),
                    ],
                  ),
                ],
                section(
                  '2. Su administrador',
                  Icons.admin_panel_settings_rounded,
                ),
                TextFormField(
                  controller: _adminName,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del administrador',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                    border: OutlineInputBorder(),
                  ),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _adminEmail,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Correo del administrador',
                    prefixIcon: Icon(Icons.mail_outline_rounded),
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value?.contains('@') == true
                      ? null
                      : 'Ingresa un correo válido',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _adminPassword,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Contraseña inicial (mínimo 8 caracteres)',
                    helperText:
                        'Compártela con el administrador por un medio seguro.',
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      tooltip: _obscurePassword
                          ? 'Mostrar contraseña'
                          : 'Ocultar contraseña',
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  validator: (value) => (value?.length ?? 0) >= 8
                      ? null
                      : 'Usa al menos 8 caracteres',
                ),
                if (auth.message != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    auth.message!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
                const SizedBox(height: 20),
                FilledButton.icon(
                  key: PlatformAdminScreen.submitKey,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                  ),
                  onPressed: _sending ? null : _createNeighborhood,
                  icon: _sending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          _existing
                              ? Icons.how_to_reg_rounded
                              : Icons.add_home_work_rounded,
                        ),
                  label: Text(
                    _existing ? 'Asignar administrador' : 'Crear barrio',
                  ),
                ),
              ],
            ),
          ),
          if (_created case final created?) ...[
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _lastWasExisting
                          ? 'Administrador asignado a ${created.neighborhoodName}'
                          : 'Barrio creado: ${created.neighborhoodName}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text('Administrador: ${created.adminFullName}'),
                    Text('Correo: ${created.adminEmail}'),
                    const SizedBox(height: 12),
                    SelectableText(
                      'Código de invitación: ${created.joinCode}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: created.joinCode),
                          );
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Código copiado')),
                            );
                          }
                        },
                        icon: const Icon(Icons.copy_rounded),
                        label: const Text('Copiar código'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Lista real de barrios: nombre, código, si tiene junta y si está en emergencia.
class _NeighborhoodsSection extends StatelessWidget {
  const _NeighborhoodsSection({
    required this.neighborhoods,
    required this.loading,
    required this.error,
    required this.onRefresh,
    required this.onAssignAdmin,
  });

  final List<NeighborhoodSummary>? neighborhoods;
  final bool loading;
  final String? error;
  final VoidCallback onRefresh;
  final ValueChanged<NeighborhoodSummary> onAssignAdmin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = neighborhoods;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                list == null ? 'Barrios' : 'Barrios (${list.length})',
                style: theme.textTheme.titleLarge,
              ),
            ),
            IconButton(
              tooltip: 'Actualizar lista',
              onPressed: loading ? null : onRefresh,
              icon: loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (error != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  TextButton(
                    onPressed: onRefresh,
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            ),
          )
        else if (list == null)
          const SizedBox.shrink()
        else if (list.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Todavía no hay barrios. Crea el primero aquí abajo.',
                style: theme.textTheme.bodyLarge,
              ),
            ),
          )
        else
          for (final n in list)
            Card(
              key: PlatformAdminScreen.neighborhoodKey(n.id),
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(n.name, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        InputChip(
                          avatar: const Icon(Icons.vpn_key_rounded, size: 18),
                          label: Text(n.inviteCode),
                          tooltip: 'Copiar código',
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: n.inviteCode),
                            );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Código ${n.inviteCode} copiado',
                                  ),
                                ),
                              );
                            }
                          },
                        ),
                        Chip(
                          avatar: Icon(
                            n.hasAdmin
                                ? Icons.verified_user_rounded
                                : Icons.person_off_rounded,
                            size: 18,
                          ),
                          label: Text(
                            n.hasAdmin ? 'Con junta' : 'Sin administrador',
                          ),
                        ),
                        if (n.isEmergencyActive)
                          const Chip(
                            avatar: Icon(Icons.warning_amber_rounded, size: 18),
                            label: Text('En emergencia'),
                          ),
                      ],
                    ),
                    if (!n.hasAdmin) ...[
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: () => onAssignAdmin(n),
                        icon: const Icon(Icons.person_add_alt_1_rounded),
                        label: const Text('Asignar administrador'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
      ],
    );
  }
}
