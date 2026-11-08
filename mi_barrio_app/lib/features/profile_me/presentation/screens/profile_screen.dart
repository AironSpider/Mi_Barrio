import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/barrio_context/tenant_session.dart';
import '../../../../core/sync_manager/pending_changes.dart';
import '../../../../core/ui_kit/app_theme.dart';
import '../../../../core/ui_kit/sync_status_chip.dart';
import '../../../auth_barrio/presentation/providers/auth_provider.dart';
import '../../data/profile_local_storage.dart';
import '../../data/user_profile_model.dart';
import 'edit_profile_screen.dart';
import 'history_screen.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key, this.storage});

  final ProfileLocalStorage? storage;

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late final ProfileLocalStorage _storage;
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();

  UserProfileModel? _profile;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _storage = widget.storage ?? ProfileLocalStorage();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_loadProfile());
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final profile = await _storage.getProfile(TenantSession.instance.userId);
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _nameController.text = profile?.fullName ?? '';
        _phoneController.text = profile?.phone ?? '';
        _addressController.text = profile?.addressReference ?? '';
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _saveProfile() async {
    if (_isSaving || _nameController.text.trim().isEmpty) return;
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      final session = TenantSession.instance;
      // saveProfile reescribe el perfil completo: lo que esta pantalla no edita
      // (redes, perfil de publicador, ubicación) se conserva tal cual estaba.
      final previous = _profile;
      final profile = await _storage.saveProfile(
        userId: session.userId,
        tenantId: session.tenantId,
        fullName: _nameController.text,
        phone: _phoneController.text,
        addressReference: _addressController.text,
        homeLat: previous?.homeLat ?? session.centerLat,
        homeLng: previous?.homeLng ?? session.centerLng,
        email: previous?.email,
        emailContacto: previous?.emailContacto,
        whatsapp: previous?.whatsapp,
        facebookUrl: previous?.facebookUrl,
        instagramUrl: previous?.instagramUrl,
        publisherType: previous?.publisherType,
        publisherCategory: previous?.publisherCategory,
        publisherName: previous?.publisherName,
      );
      if (!mounted) return;
      setState(() => _profile = profile);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Perfil guardado; se sincronizará en segundo plano.'),
          ),
        );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Si hay cambios sin sincronizar, pide confirmación antes de cerrar sesión.
  Future<void> _logout() async {
    final n = await PendingChanges.count(TenantSession.instance.tenantId);
    final aviso = PendingChanges.logoutWarning(n);
    if (aviso != null) {
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Cambios sin sincronizar'),
          content: Text(aviso),
          actions: [
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Seguir aquí'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Cerrar sesión'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    if (!mounted) return;
    await ref.read(authProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colores = MiBarrioColors.of(context);
    final user = ref.watch(authProvider).user;
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final name = _profile?.fullName ?? user?.fullName ?? '';
    final initials =
        _profile?.initials ??
        name
            .trim()
            .split(RegExp(r'\s+'))
            .where((p) => p.isNotEmpty)
            .take(2)
            .map((p) => p[0].toUpperCase())
            .join();

    Widget section(String title, {String? subtitle}) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          if (subtitle != null)
            Text(
              subtitle,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );

    return ListView(
      // Abajo, espacio para el botón "Pedir ayuda" (visible en emergencia).
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [
        // ── Quién soy ──
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 32,
                  backgroundColor: colores.accentSoft,
                  child: Text(
                    initials.isEmpty ? '?' : initials,
                    style: theme.textTheme.titleLarge?.copyWith(
                      color: colores.accentText,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          name.isEmpty ? 'Mi perfil' : name,
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                      if (user != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          user.role.label,
                          style: theme.textTheme.bodyMedium,
                        ),
                        if ((user.tenantName ?? '').isNotEmpty)
                          Text(
                            user.tenantName!,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                      if (_profile != null) ...[
                        const SizedBox(height: 8),
                        SyncStatusChip.fromPending(_profile!.isPending),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── Datos personales ──
        section(
          'Datos personales',
          subtitle:
              'Se guardan en tu teléfono y se envían cuando hay conexión.',
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nombre y apellido',
                    prefixIcon: Icon(Icons.badge_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Teléfono (opcional)',
                    prefixIcon: Icon(Icons.call_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _addressController,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Referencia de domicilio (opcional)',
                    prefixIcon: Icon(Icons.home_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      'No se pudo guardar o cargar el perfil: $_error',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.error,
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: _isSaving
                          ? null
                          : () => unawaited(_loadProfile()),
                      child: const Text('Volver a intentar'),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  onPressed: _isSaving || _isLoading ? null : _saveProfile,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_rounded),
                  label: const Text('Guardar perfil'),
                ),
              ],
            ),
          ),
        ),

        // ── Más opciones ──
        section('Más opciones'),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              ListTile(
                key: const ValueKey('open_edit_profile'),
                minTileHeight: 64,
                leading: Icon(
                  Icons.manage_accounts_rounded,
                  color: colores.accentText,
                ),
                title: const Text('Redes y perfil de publicador'),
                subtitle: const Text('WhatsApp, correo, Facebook, tu negocio'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => EditProfileScreen(storage: _storage),
                    ),
                  );
                  if (mounted) unawaited(_loadProfile());
                },
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                key: const ValueKey('open_history'),
                minTileHeight: 64,
                leading: Icon(Icons.history_rounded, color: colores.accentText),
                title: const Text('Mi historial'),
                subtitle: const Text(
                  'Tus servicios, favores y pedidos de ayuda',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const HistoryScreen(),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        OutlinedButton.icon(
          key: const ValueKey('logout_button'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            foregroundColor: scheme.error,
            side: BorderSide(color: scheme.error.withValues(alpha: 0.5)),
          ),
          onPressed: () => unawaited(_logout()),
          icon: const Icon(Icons.logout_rounded),
          label: const Text('Cerrar sesión'),
        ),
      ],
    );
  }
}
