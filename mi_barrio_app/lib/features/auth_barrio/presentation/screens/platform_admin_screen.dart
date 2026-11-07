import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/user_entity.dart';
import '../providers/auth_provider.dart';

class PlatformAdminScreen extends ConsumerStatefulWidget {
  const PlatformAdminScreen({super.key, required this.user});

  final UserEntity user;

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

  @override
  void dispose() {
    _neighborhood.dispose();
    _existingJoinCode.dispose();
    _adminName.dispose();
    _adminEmail.dispose();
    _adminPassword.dispose();
    _latitude.dispose();
    _longitude.dispose();
    super.dispose();
  }

  Future<void> _createNeighborhood() async {
    if (!_formKey.currentState!.validate() || _sending) return;
    setState(() {
      _sending = true;
      _created = null;
    });
    final created = await ref
        .read(authProvider.notifier)
        .createNeighborhood(
          neighborhoodName: _neighborhood.text,
          existingJoinCode: _existingJoinCode.text,
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
    }
  }

  String? _required(String? value) {
    if (_existingJoinCode.text.trim().isNotEmpty) return null;
    return value == null || value.trim().isEmpty ? 'Campo obligatorio' : null;
  }

  String? _coordinate(
    String? value, {
    required double min,
    required double max,
  }) {
    if (_existingJoinCode.text.trim().isNotEmpty) return null;
    final number = double.tryParse(value?.trim() ?? '');
    if (number == null || number < min || number > max) {
      return 'Ingresa un valor entre $min y $max';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
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
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Hola, ${widget.user.fullName}',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'Crea un barrio y su administrador, o asigna un administrador al '
            'barrio existente usando su código.',
          ),
          const SizedBox(height: 20),
          Form(
            key: _formKey,
            child: Column(
              children: [
                TextFormField(
                  controller: _neighborhood,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del barrio',
                    border: OutlineInputBorder(),
                  ),
                  validator: _required,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _existingJoinCode,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Código de barrio existente (opcional)',
                    helperText: 'Déjalo vacío para crear un barrio nuevo. Úsalo para asignar el barrio de demostración.',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _adminName,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del administrador del barrio',
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
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value?.contains('@') == true
                      ? null
                      : 'Ingresa un correo válido',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _adminPassword,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Contraseña inicial (mínimo 8 caracteres)',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => (value?.length ?? 0) >= 8
                      ? null
                      : 'Usa al menos 8 caracteres',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _latitude,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Latitud del centro del barrio',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => _coordinate(value, min: -90, max: 90),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _longitude,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Longitud del centro del barrio',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => _coordinate(value, min: -180, max: 180),
                  onChanged: (_) => setState(() {}),
                ),
                if (auth.message != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    auth.message!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _sending ? null : _createNeighborhood,
                    child: _sending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Crear barrio / asignar administrador'),
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
                      'Barrio creado: ${created.neighborhoodName}',
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
