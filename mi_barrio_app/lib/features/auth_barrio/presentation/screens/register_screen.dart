import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/ui_kit/app_theme.dart';
import '../../data/datasources/auth_remote_datasource.dart';
import '../../domain/entities/user_entity.dart';
import '../providers/auth_provider.dart';
import '../../../legal/legal_screens.dart';
import '../register_draft.dart';
import '../widgets/account_widgets.dart';
import '../widgets/auth_validators.dart';

/// Busca el nombre del barrio de un código (null = no existe).
typedef NeighborhoodLookup = Future<String?> Function(String joinCode);

/// Crear cuenta: código del barrio, rol, Google o correo y contraseña, con el aviso
/// de términos.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key, this.lookupNeighborhood});

  /// Por defecto, `GET /api/v1/tenants/by-code/{code}` (ruta pública).
  final NeighborhoodLookup? lookupNeighborhood;

  static const joinCodeStatusKey = ValueKey('register_join_code_status');
  static const vecinoCardKey = ValueKey('register_role_vecino');
  static const comercianteCardKey = ValueKey('register_role_comerciante');
  static const confirmFieldKey = ValueKey('register_confirm_password');
  static const submitKey = ValueKey('register_submit');

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _joinCode = TextEditingController();
  final _joinCodeField = GlobalKey<FormFieldState<String>>();
  UserRole _role = UserRole.vecino;
  bool _obscurePassword = true;
  bool _googleBusy = false;
  String? _googleError;

  @override
  void initState() {
    super.initState();
    _password.addListener(() => setState(() {}));
    _loadDraft();
  }

  /// "Volver para cambiar datos": vuelve con lo que había escrito (la
  /// contraseña no se guarda: se escribe de nuevo).
  Future<void> _loadDraft() async {
    final draft = await RegisterDraft.load();
    if (draft == null || !mounted) return;
    setState(() {
      if (_joinCode.text.isEmpty) _joinCode.text = draft.joinCode;
      if (_name.text.isEmpty) _name.text = draft.fullName;
      if (_email.text.isEmpty) _email.text = draft.email;
      _role = draft.role == UserRole.comerciante.apiValue
          ? UserRole.comerciante
          : UserRole.vecino;
    });
    if (draft.joinCode.isNotEmpty) _onCodeChanged(draft.joinCode);
  }

  /// Con Google no hace falta nombre, correo ni contraseña: solo el barrio y el rol.
  /// Casilla de Términos: obligatoria para las dos formas de crear la cuenta.
  final _termsField = GlobalKey<FormFieldState<bool>>();

  bool get _termsAccepted => _termsField.currentState?.value == true;

  /// Si falta la casilla, la muestra (puede estar arriba, fuera de la vista).
  bool _checkTerms() {
    final ok = _termsField.currentState?.validate() ?? false;
    final target = _termsField.currentContext;
    if (!ok && target != null) {
      Scrollable.ensureVisible(
        target,
        alignment: 0.3,
        duration: const Duration(milliseconds: 300),
      );
    }
    return ok;
  }

  Future<void> _google() async {
    if (!(_joinCodeField.currentState?.validate() ?? false)) {
      setState(() => _googleError = 'Primero escribe el código de tu barrio.');
      return;
    }
    if (!_checkTerms()) return;
    setState(() {
      _googleBusy = true;
      _googleError = null;
    });
    final error = await continueWithGoogle(
      context,
      ref,
      joinCode: _joinCode.text,
      role: _role,
      acceptedTerms: _termsAccepted,
    );
    if (!mounted) return;
    if (error == null && ref.read(authProvider).user != null) {
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }
    setState(() {
      _googleBusy = false;
      _googleError = error;
    });
  }

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
    _confirm.dispose();
    _joinCode.dispose();
    super.dispose();
  }

  /// true después de tocar "Crear cuenta": recién ahí se muestra el error
  /// del servidor (antes salía el de un login fallido anterior).
  bool _triedRegister = false;

  Future<void> _register() async {
    setState(() => _triedRegister = true);
    final valid = _formKey.currentState!.validate();
    if (!_checkTerms() || !valid) return;
    await RegisterDraft.save(
      RegisterDraft(
        joinCode: _joinCode.text.trim(),
        fullName: _name.text.trim(),
        email: _email.text.trim(),
        role: _role.apiValue,
      ),
    );
    await ref
        .read(authProvider.notifier)
        .register(
          fullName: _name.text,
          email: _email.text,
          password: _password.text,
          role: _role,
          joinCode: _joinCode.text,
          acceptedTerms: _termsAccepted,
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
    final loading = auth.status == AuthStatus.loading || _googleBusy;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Crear cuenta'),
        leading: AuthBackButton(
          tooltip: 'Volver al inicio de sesión',
          onPressed: loading ? null : () => Navigator.of(context).maybePop(),
        ),
        leadingWidth: 64,
      ),
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
                      key: _joinCodeField,
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
                      validator: AuthValidators.joinCode,
                    ),
                    const SizedBox(height: 6),
                    _JoinCodeStatus(
                      key: RegisterScreen.joinCodeStatusKey,
                      status: _codeStatus,
                      neighborhoodName: _neighborhoodName,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '¿Cómo vas a usar Mi Barrio?',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    RoleChoice(
                      role: _role,
                      vecinoKey: RegisterScreen.vecinoCardKey,
                      comercianteKey: RegisterScreen.comercianteCardKey,
                      onChanged: loading
                          ? null
                          : (role) => setState(() => _role = role),
                    ),
                    ...[
                      const SizedBox(height: 16),
                      TermsAcceptanceField(
                        key: _termsField,
                        enabled: !loading,
                      ),
                      const SizedBox(height: 16),
                      GoogleSignInButton(
                        label: 'Registrarme con Google',
                        busy: _googleBusy,
                        onPressed: loading ? null : _google,
                      ),
                      if (_googleError != null) ...[
                        const SizedBox(height: 8),
                        Semantics(
                          // El lector de pantalla lo anuncia apenas aparece.
                          liveRegion: true,
                          child: Text(
                          _googleError!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      const OrDivider(),
                      const SizedBox(height: 4),
                      Text(
                        'O crea tu cuenta con correo y contraseña:',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _name,
                      textInputAction: TextInputAction.next,
                      enabled: !loading,
                      textCapitalization: TextCapitalization.words,
                      autofillHints: const [AutofillHints.name],
                      decoration: const InputDecoration(
                        labelText: 'Nombre completo',
                        prefixIcon: Icon(Icons.person_outline_rounded),
                        border: OutlineInputBorder(),
                      ),
                      validator: AuthValidators.fullName,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _email,
                      textInputAction: TextInputAction.next,
                      enabled: !loading,
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                        labelText: 'Correo electrónico',
                        helperText: 'Te enviaremos un código para confirmarlo',
                        prefixIcon: Icon(Icons.mail_outline_rounded),
                        border: OutlineInputBorder(),
                      ),
                      validator: AuthValidators.newEmail,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _password,
                      textInputAction: TextInputAction.next,
                      enabled: !loading,
                      obscureText: _obscurePassword,
                      autofillHints: const [AutofillHints.newPassword],
                      decoration: InputDecoration(
                        labelText: 'Contraseña',
                        helperText: '8 o más caracteres, con letras y números',
                        prefixIcon: const Icon(Icons.lock_outline_rounded),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          tooltip: _obscurePassword
                              ? 'Mostrar contraseña'
                              : 'Ocultar contraseña',
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
                      validator: AuthValidators.newPassword,
                    ),
                    PasswordStrengthMeter(password: _password.text),
                    const SizedBox(height: 14),
                    TextFormField(
                      key: RegisterScreen.confirmFieldKey,
                      controller: _confirm,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => loading ? null : _register(),
                      enabled: !loading,
                      obscureText: _obscurePassword,
                      decoration: const InputDecoration(
                        labelText: 'Repite la contraseña',
                        prefixIcon: Icon(Icons.lock_outline_rounded),
                        border: OutlineInputBorder(),
                      ),
                      validator: AuthValidators.confirmPassword(
                        () => _password.text,
                      ),
                    ),
                    // Solo el error de ESTE registro (no el de un login
                    // fallido antes de abrir esta pantalla).
                    if (_triedRegister && auth.message != null) ...[
                      const SizedBox(height: 12),
                      Semantics(
                        // El lector de pantalla lo anuncia apenas aparece.
                        liveRegion: true,
                        child: Text(
                        auth.message!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    FilledButton(
                      key: RegisterScreen.submitKey,
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
