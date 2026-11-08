import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/ui_kit/app_theme.dart';
import '../../data/datasources/auth_remote_datasource.dart';
import '../../domain/entities/user_entity.dart';
import '../providers/auth_provider.dart';

/// Busca el nombre del barrio de un código (null = no existe).
typedef NeighborhoodLookup = Future<String?> Function(String joinCode);

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key, this.lookupNeighborhood});

  /// Por defecto, `GET /api/v1/tenants/by-code/{code}` (ruta pública).
  final NeighborhoodLookup? lookupNeighborhood;

  static const joinCodeStatusKey = ValueKey('register_join_code_status');
  static const vecinoCardKey = ValueKey('register_role_vecino');
  static const comercianteCardKey = ValueKey('register_role_comerciante');

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _joinCode = TextEditingController();
  UserRole _role = UserRole.vecino;
  bool _obscurePassword = true;

  // Confirmación del barrio mientras se escribe el código.
  late final NeighborhoodLookup _lookup =
      widget.lookupNeighborhood ??
      AuthRemoteDatasource().lookupNeighborhoodName;
  Timer? _lookupDebounce;
  _CodeStatus _codeStatus = _CodeStatus.empty;
  String? _neighborhoodName;
  int _lookupVersion = 0;

  void _onCodeChanged(String value) {
    _lookupDebounce?.cancel();
    final code = value.trim();
    if (code.length < 3) {
      setState(() => _codeStatus = _CodeStatus.empty);
      return;
    }
    setState(() => _codeStatus = _CodeStatus.checking);
    _lookupDebounce = Timer(
      const Duration(milliseconds: 600),
      () => _check(code),
    );
  }

  Future<void> _check(String code) async {
    final version = ++_lookupVersion;
    _CodeStatus status;
    String? name;
    try {
      name = await _lookup(code);
      status = name == null ? _CodeStatus.notFound : _CodeStatus.found;
    } catch (_) {
      status = _CodeStatus.unverified;
    }
    if (!mounted || version != _lookupVersion) return;
    setState(() {
      _codeStatus = status;
      _neighborhoodName = name;
    });
  }

  @override
  void dispose() {
    _lookupDebounce?.cancel();
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _joinCode.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    await ref
        .read(authProvider.notifier)
        .register(
          fullName: _name.text,
          email: _email.text,
          password: _password.text,
          role: _role,
          joinCode: _joinCode.text,
        );
    if (mounted &&
        ref.read(authProvider).status != AuthStatus.error &&
        ref.read(authProvider).status != AuthStatus.unauthenticated) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final loading = auth.status == AuthStatus.loading;

    return Scaffold(
      appBar: AppBar(title: const Text('Crear cuenta')),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Únete a tu barrio',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Pide el código a tu junta vecinal. Con él te conectas con '
                      'los vecinos de tu zona.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _joinCode,
                      enabled: !loading,
                      textCapitalization: TextCapitalization.characters,
                      onChanged: _onCodeChanged,
                      decoration: const InputDecoration(
                        labelText: 'Código de tu barrio',
                        hintText: 'Ej: BARRIO-01',
                        prefixIcon: Icon(Icons.vpn_key_outlined),
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) => (value?.trim().length ?? 0) >= 3
                          ? null
                          : 'Ingresa el código de invitación del barrio',
                    ),
                    const SizedBox(height: 6),
                    _JoinCodeStatus(
                      key: RegisterScreen.joinCodeStatusKey,
                      status: _codeStatus,
                      neighborhoodName: _neighborhoodName,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _name,
                      enabled: !loading,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Nombre completo',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) => (value?.trim().length ?? 0) >= 2
                          ? null
                          : 'Ingresa tu nombre completo',
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _email,
                      enabled: !loading,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Correo electrónico',
                        prefixIcon: Icon(Icons.mail_outline_rounded),
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) => (value?.contains('@') ?? false)
                          ? null
                          : 'Correo inválido',
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _password,
                      enabled: !loading,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Contraseña (mínimo 8 caracteres)',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
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
                    const SizedBox(height: 14),
                    const SizedBox(height: 14),
                    Text(
                      '¿Cómo vas a usar Mi Barrio?',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    _RoleCard(
                      key: RegisterScreen.vecinoCardKey,
                      icon: Icons.home_rounded,
                      title: 'Soy vecino',
                      subtitle: 'Pido y ofrezco ayuda, y encuentro oficios.',
                      selected: _role == UserRole.vecino,
                      onTap: loading
                          ? null
                          : () => setState(() => _role = UserRole.vecino),
                    ),
                    const SizedBox(height: 10),
                    _RoleCard(
                      key: RegisterScreen.comercianteCardKey,
                      icon: Icons.storefront_rounded,
                      title: 'Tengo un oficio o negocio',
                      subtitle: 'Ofrezco mis servicios a mis vecinos.',
                      selected: _role == UserRole.comerciante,
                      onTap: loading
                          ? null
                          : () => setState(() => _role = UserRole.comerciante),
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
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: loading ? null : _register,
                      child: loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Crear cuenta'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Tarjeta grande y tocable para elegir el tipo de cuenta (en vez de un
/// desplegable): se entiende sin leer mucho y es fácil de tocar.
class _RoleCard extends StatelessWidget {
  const _RoleCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final texto = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? scheme.primaryContainer : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outline,
            width: selected ? 2.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 36,
                    color: selected
                        ? scheme.onPrimaryContainer
                        : scheme.primary,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: texto.titleMedium?.copyWith(
                            color: selected ? scheme.onPrimaryContainer : null,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: texto.bodyMedium?.copyWith(
                            color: selected
                                ? scheme.onPrimaryContainer
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: selected ? scheme.primary : scheme.outline,
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

enum _CodeStatus { empty, checking, found, notFound, unverified }

/// Línea bajo el código: "Te vas a unir a: …" o qué pasa con el código.
/// Siempre ícono + texto (nunca solo color).
class _JoinCodeStatus extends StatelessWidget {
  const _JoinCodeStatus({
    super.key,
    required this.status,
    this.neighborhoodName,
  });

  final _CodeStatus status;
  final String? neighborhoodName;

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final (IconData? icon, String text, Color color) = switch (status) {
      _CodeStatus.empty => (null, '', scheme.onSurfaceVariant),
      _CodeStatus.checking => (
        Icons.search_rounded,
        'Buscando tu barrio…',
        scheme.onSurfaceVariant,
      ),
      _CodeStatus.found => (
        Icons.check_circle_rounded,
        'Te vas a unir a: ${neighborhoodName ?? ''}',
        AppPalette.syncSynced,
      ),
      _CodeStatus.notFound => (
        Icons.error_outline_rounded,
        'No encontramos un barrio con ese código. Revísalo con tu junta.',
        scheme.error,
      ),
      _CodeStatus.unverified => (
        Icons.cloud_off_rounded,
        'No pudimos verificar el código ahora. Puedes continuar igual.',
        scheme.onSurfaceVariant,
      ),
    };
    if (icon == null) return const SizedBox.shrink();
    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: texto.bodyMedium?.copyWith(
                color: color,
                fontWeight: status == _CodeStatus.found
                    ? FontWeight.w600
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
