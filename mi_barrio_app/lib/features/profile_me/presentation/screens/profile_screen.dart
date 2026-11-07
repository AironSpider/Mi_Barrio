import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/barrio_context/tenant_session.dart';
import '../../../../core/ui_kit/sync_status_chip.dart';
import '../../data/profile_local_storage.dart';
import '../../data/user_profile_model.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.storage});

  final ProfileLocalStorage? storage;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
      children: [
        Text('Mi perfil', style: theme.textTheme.headlineSmall),
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
      ],
    );
  }
}
