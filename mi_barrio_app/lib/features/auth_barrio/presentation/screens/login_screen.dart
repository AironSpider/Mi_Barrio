import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/ui_kit/app_theme.dart';
import '../providers/auth_provider.dart';
import '../widgets/account_widgets.dart';
import 'forgot_password_screen.dart';
import 'register_screen.dart';

/// Inicio de sesión.
///
/// - Encabezado con el logo real y el color de la marca.
/// - Campos con ícono, teclado correcto, autocompletado y "Siguiente" → "Ingresar".
/// - Errores en lenguaje simple (nunca detalles técnicos), anunciados al lector
///   de pantalla, que se ocultan al volver a escribir.
/// - Si el servidor tarda (Render gratis "despierta" en ~30 s), se avisa.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  static const emailFieldKey = ValueKey('login_email');
  static const passwordFieldKey = ValueKey('login_password');
  static const submitKey = ValueKey('login_submit');
  static const errorKey = ValueKey('login_error');
  static const slowServerKey = ValueKey('login_slow_server');
  static const forgotPasswordKey = ValueKey('login_forgot_password');
  static const googleErrorKey = ValueKey('login_google_error');

  /// Después de este tiempo cargando se muestra el aviso de servidor lento.
  static const slowServerAfter = Duration(seconds: 5);

  /// Convierte el mensaje del servidor o de la red en uno para vecinos.
  static String friendlyError(String raw) {
    final text = raw.toLowerCase();
    if (text.contains('no pudimos contactar') ||
        text.contains('no se pudo conectar') ||
        text.contains('socketexception') ||
        text.contains('failed host lookup') ||
        text.contains('connection')) {
      return 'No pudimos conectar con Mi Barrio. Revisa tu internet y vuelve a '
          'intentarlo.';
    }
    if (text.contains('incorrectos')) {
      return 'El correo o la contraseña no coinciden. Revísalos e intenta de nuevo.';
    }
    if (text.contains('demasiados intentos')) return raw;
    if (text.contains('barrio activo') || text.contains('no está disponible')) {
      return 'Tu cuenta ya no pertenece a un barrio activo. Consulta con tu '
          'junta vecinal.';
    }
    if (text.contains('servidor respondió 5') ||
        text.contains('servidor respondio 5')) {
      return 'Mi Barrio tiene un problema en este momento. Intenta de nuevo en '
          'unos minutos.';
    }
    if (text.contains('restaurar la sesión')) {
      return 'No pudimos abrir tu sesión guardada. Ingresa de nuevo.';
    }
    return raw;
  }

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _obscurePassword = true;
  bool _submitted = false;

  /// El vecino volvió a escribir: el error anterior ya no aplica.
  bool _errorDismissed = false;

  bool _googleBusy = false;
  String? _googleError;

  Future<void> _google() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _googleBusy = true;
      _googleError = null;
      _errorDismissed = true;
    });
    final error = await continueWithGoogle(context, ref);
    if (!mounted) return;
    setState(() {
      _googleBusy = false;
      _googleError = error;
    });
  }

  static final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');

  @override
  void initState() {
    super.initState();
    for (final c in [_email, _password]) {
      c.addListener(_onEdit);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  void _onEdit() {
    if (!_errorDismissed && ref.read(authProvider).message != null) {
      setState(() => _errorDismissed = true);
    }
    if (_googleError != null) setState(() => _googleError = null);
  }

  Future<void> _login() async {
    setState(() => _submitted = true);
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _errorDismissed = false);
    await ref
        .read(authProvider.notifier)
        .login(email: _email.text.trim(), password: _password.text);
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Escribe tu correo';
    return _emailPattern.hasMatch(email)
        ? null
        : 'Revisa tu correo (ejemplo: nombre@correo.com)';
  }

  String? _validatePassword(String? value) {
    final password = value ?? '';
    if (password.isEmpty) return 'Escribe tu contraseña';
    return password.length >= 8
        ? null
        : 'Tu contraseña tiene al menos 8 caracteres';
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final loading = auth.status == AuthStatus.loading || _googleBusy;
    final message = auth.message;
    final showError = message != null && !_errorDismissed && !loading;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                children: [
                  const _BrandHeader(),
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                        child: AutofillGroup(
                          child: Form(
                            key: _formKey,
                            autovalidateMode: _submitted
                                ? AutovalidateMode.onUserInteraction
                                : AutovalidateMode.disabled,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Semantics(
                                  header: true,
                                  child: Text(
                                    'Ingresa a tu barrio',
                                    style: theme.textTheme.titleLarge,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Usa el correo y la contraseña con los que te '
                                  'registraste.',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                TextFormField(
                                  key: LoginScreen.emailFieldKey,
                                  controller: _email,
                                  enabled: !loading,
                                  keyboardType: TextInputType.emailAddress,
                                  textInputAction: TextInputAction.next,
                                  autocorrect: false,
                                  enableSuggestions: false,
                                  autofillHints: const [AutofillHints.email],
                                  style: theme.textTheme.bodyLarge,
                                  decoration: const InputDecoration(
                                    labelText: 'Correo',
                                    hintText: 'nombre@correo.com',
                                    prefixIcon: Icon(
                                      Icons.mail_outline_rounded,
                                    ),
                                    border: OutlineInputBorder(),
                                  ),
                                  validator: _validateEmail,
                                  onFieldSubmitted: (_) =>
                                      _passwordFocus.requestFocus(),
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  key: LoginScreen.passwordFieldKey,
                                  controller: _password,
                                  focusNode: _passwordFocus,
                                  enabled: !loading,
                                  obscureText: _obscurePassword,
                                  textInputAction: TextInputAction.done,
                                  autocorrect: false,
                                  enableSuggestions: false,
                                  autofillHints: const [AutofillHints.password],
                                  style: theme.textTheme.bodyLarge,
                                  decoration: InputDecoration(
                                    labelText: 'Contraseña',
                                    prefixIcon: const Icon(
                                      Icons.lock_outline_rounded,
                                    ),
                                    border: const OutlineInputBorder(),
                                    suffixIcon: IconButton(
                                      tooltip: _obscurePassword
                                          ? 'Mostrar contraseña'
                                          : 'Ocultar contraseña',
                                      onPressed: () => setState(
                                        () => _obscurePassword =
                                            !_obscurePassword,
                                      ),
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility_outlined
                                            : Icons.visibility_off_outlined,
                                      ),
                                    ),
                                  ),
                                  validator: _validatePassword,
                                  onFieldSubmitted: (_) => _login(),
                                ),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    key: LoginScreen.forgotPasswordKey,
                                    onPressed: loading
                                        ? null
                                        : () => Navigator.of(context).push(
                                            MaterialPageRoute<void>(
                                              builder: (_) =>
                                                  ForgotPasswordScreen(
                                                    initialEmail: _email.text
                                                        .trim(),
                                                  ),
                                            ),
                                          ),
                                    child: const Text(
                                      '¿Olvidaste tu contraseña?',
                                    ),
                                  ),
                                ),
                                AnimatedSize(
                                  duration: const Duration(milliseconds: 200),
                                  child: showError
                                      ? Padding(
                                          padding: const EdgeInsets.only(
                                            top: 16,
                                          ),
                                          child: _ErrorBox(
                                            message: LoginScreen.friendlyError(
                                              message,
                                            ),
                                          ),
                                        )
                                      : const SizedBox(width: double.infinity),
                                ),
                                const SizedBox(height: 24),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    minHeight: 56,
                                  ),
                                  child: FilledButton(
                                    key: LoginScreen.submitKey,
                                    onPressed: loading ? null : _login,
                                    child: loading
                                        ? const _LoadingLabel()
                                        : const Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  'Ingresar',
                                                  textAlign: TextAlign.center,
                                                ),
                                              ),
                                              SizedBox(width: 8),
                                              Icon(Icons.arrow_forward_rounded),
                                            ],
                                          ),
                                  ),
                                ),
                                if (loading && !_googleBusy)
                                  const _SlowServerHint(),
                                ...[
                                  const SizedBox(height: 20),
                                  const OrDivider(),
                                  const SizedBox(height: 20),
                                  GoogleSignInButton(
                                    busy: _googleBusy,
                                    onPressed: loading ? null : _google,
                                  ),
                                  if (_googleError != null) ...[
                                    const SizedBox(height: 12),
                                    KeyedSubtree(
                                      key: LoginScreen.googleErrorKey,
                                      child: _ErrorBox(message: _googleError!),
                                    ),
                                  ],
                                ],
                                const SizedBox(height: 28),
                                Text(
                                  '¿Eres nuevo en Mi Barrio?',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    minHeight: 56,
                                  ),
                                  child: OutlinedButton.icon(
                                    onPressed: loading
                                        ? null
                                        : () => Navigator.of(context).push(
                                            MaterialPageRoute<void>(
                                              builder: (_) =>
                                                  const RegisterScreen(),
                                            ),
                                          ),
                                    icon: const Icon(
                                      Icons.person_add_alt_1_rounded,
                                    ),
                                    label: const Text(
                                      'Crear una cuenta',
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Necesitas el código de tu barrio. Pídeselo a '
                                  'tu junta vecinal.',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
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

/// Encabezado de marca: el logo (casa y vecinos), el nombre y el lema, sobre
/// blanco como en el ícono de la app, con el trazo naranja del logo.
class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppPalette.card,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      child: Column(
        children: [
          Image.asset(
            'assets/images/logo_mi_barrio.png',
            height: 140,
            width: 140,
            excludeFromSemantics: true,
            errorBuilder: (_, _, _) => Icon(
              Icons.holiday_village_rounded,
              size: 96,
              color: scheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          Semantics(
            header: true,
            child: Text(
              'Mi Barrio',
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineMedium?.copyWith(
                color: AppPalette.textPrimary,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
          ),
          const SizedBox(height: 6),
          // Trazo naranja del logo: firma visual de la marca.
          Container(
            width: 72,
            height: 4,
            decoration: BoxDecoration(
              color: AppPalette.brandOrange,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Tu barrio conectado, aunque no haya señal.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: AppPalette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Error con ícono + texto, anunciado al lector de pantalla.
class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = MiBarrioColors.of(context);
    return Semantics(
      key: LoginScreen.errorKey,
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colores.failedBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colores.syncFailed.withValues(alpha: 0.4)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline_rounded, color: colores.syncFailed),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colores.syncFailed,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Ingresando…" con indicador, legible (no solo un círculo girando).
class _LoadingLabel extends StatelessWidget {
  const _LoadingLabel();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface;
    return Semantics(
      label: 'Ingresando',
      excludeSemantics: true,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: color),
          ),
          const SizedBox(width: 12),
          const Flexible(child: Text('Ingresando…')),
        ],
      ),
    );
  }
}

/// Si el ingreso tarda, explica por qué (el servidor gratis se duerme).
class _SlowServerHint extends StatefulWidget {
  const _SlowServerHint();

  @override
  State<_SlowServerHint> createState() => _SlowServerHintState();
}

class _SlowServerHintState extends State<_SlowServerHint> {
  Timer? _timer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(LoginScreen.slowServerAfter, () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      key: LoginScreen.slowServerKey,
      padding: const EdgeInsets.only(top: 12),
      child: Semantics(
        liveRegion: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.hourglass_top_rounded,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Está tardando un poco: el servidor se está activando. '
                'Puede tomar hasta 1 minuto.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
