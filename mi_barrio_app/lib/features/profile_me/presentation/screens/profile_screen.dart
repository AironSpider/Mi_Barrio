import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/barrio_context/tenant_session.dart';
import '../../../../core/sync_manager/pending_changes.dart';
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
      final profile = await _storage.saveProfile(
        userId: session.userId,
        tenantId: session.tenantId,
        fullName: _nameController.text,
        phone: _phoneController.text,
        addressReference: _addressController.text,
        homeLat: session.centerLat,
        homeLng: session.centerLng,
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
    final user = ref.watch(authProvider).user;
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      children: [
        Text('Mi perfil', style: theme.textTheme.headlineSmall),
        if (user != null) ...[
          const SizedBox(height: 8),
          Text('${user.fullName} · ${user.role.label}'),
          Text(user.tenantName ?? ''),
        ],
        const SizedBox(height: 4),
        Text(
          'Tus datos personales se guardan en este teléfono y se sincronizan cuando hay conexión.',
          style: theme.textTheme.bodyMedium,
        ),
        if (_profile != null) ...[
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: SyncStatusChip.fromPending(_profile!.isPending),
          ),
        ],
        const SizedBox(height: 20),
        TextField(
          controller: _nameController,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Nombre y apellido',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Teléfono (opcional)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _addressController,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Referencia de domicilio (opcional)',
            border: OutlineInputBorder(),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(
            'No se pudo guardar o cargar el perfil: $_error',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          TextButton(
            onPressed: _isSaving ? null : () => unawaited(_loadProfile()),
            child: const Text('Volver a intentar'),
          ),
        ],
        const SizedBox(height: 20),
        FilledButton.icon(
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
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const ValueKey('open_edit_profile'),
          onPressed: () async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => EditProfileScreen(storage: _storage)),
            );
            if (mounted) unawaited(_loadProfile());
          },
          icon: const Icon(Icons.manage_accounts_rounded),
          label: const Text('Redes y perfil de publicador'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const ValueKey('open_history'),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const HistoryScreen()),
          ),
          icon: const Icon(Icons.history_rounded),
          label: const Text('Mi historial'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const ValueKey('logout_button'),
          onPressed: () => unawaited(_logout()),
          icon: const Icon(Icons.logout_rounded),
          label: const Text('Cerrar sesión'),
        ),
      ],
    );
  }
}
