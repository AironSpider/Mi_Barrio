import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../widgets/account_widgets.dart';
import '../widgets/auth_validators.dart';

/// "¿Olvidaste tu contraseña?": 1) correo → 2) código + contraseña nueva.
/// Al terminar, el vecino queda con la sesión iniciada.
/// También sirve para crear una contraseña a quien entró con Google.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialEmail = ''});

  final String initialEmail;

  static const emailFieldKey = ValueKey('forgot_email');
  static const sendKey = ValueKey('forgot_send');
  static const codeFieldKey = ValueKey('forgot_code');
  static const passwordFieldKey = ValueKey('forgot_password');
  static const confirmFieldKey = ValueKey('forgot_confirm');
  static const saveKey = ValueKey('forgot_save');
  static const messageKey = ValueKey('forgot_message');

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _emailForm = GlobalKey<FormState>();
  final _resetForm = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.initialEmail);
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  bool _obscure = true;
  String? _error;
  int _wait = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _password.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in [_email, _code, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _wait = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _wait--);
      if (_wait <= 0) t.cancel();
    });
  }

  Future<void> _sendCode() async {
    if (!_codeSent && !_emailForm.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await ref
        .read(authProvider.notifier)
        .requestPasswordReset(_email.text.trim());
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
      if (error == null) _codeSent = true;
    });
    if (error == null) _startCountdown();
  }

  Future<void> _save() async {
    if (!_resetForm.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await ref
        .read(authProvider.notifier)
        .resetPassword(
          email: _email.text.trim(),
          code: _code.text.trim(),
          newPassword: _password.text,
        );
    if (!mounted) return;
    if (error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('¡Listo! Cambiaste tu contraseña y ya entraste.'),
        ),
      );
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    final esquema = Theme.of(context).colorScheme;
    final busyIndicator = const SizedBox(
      width: 22,
      height: 22,
      child: CircularProgressIndicator(strokeWidth: 2.5),
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recuperar contraseña'),
        leading: AuthBackButton(
          tooltip: 'Volver a inicio de sesión',
          onPressed: _busy ? null : () => Navigator.of(context).maybePop(),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _codeSent
                        ? 'Escribe el código'
                        : '¿Olvidaste tu contraseña?',
                    style: texto.headlineSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _codeSent
                        ? 'Si ${_email.text.trim()} tiene una cuenta en Mi Barrio, '
                              'te llegará un código de 6 números en unos segundos. '
                              'Escríbelo y crea tu contraseña nueva. Si no llega, '
                              'revisa "Spam" o crea una cuenta.'
                        : 'Escribe el correo de tu cuenta. Te enviaremos un código para '
                              'crear una contraseña nueva.',
                    style: texto.bodyLarge,
                  ),
                  const SizedBox(height: 20),
                  Form(
                    key: _emailForm,
                    child: TextFormField(
                      key: ForgotPasswordScreen.emailFieldKey,
                      controller: _email,
                      enabled: !_busy && !_codeSent,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(
                        labelText: 'Correo',
                        prefixIcon: Icon(Icons.mail_outline_rounded),
                        border: OutlineInputBorder(),
                      ),
                      validator: AuthValidators.email,
                      onFieldSubmitted: (_) => _sendCode(),
                    ),
                  ),
                  if (!_codeSent) ...[
                    const SizedBox(height: 20),
                    ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 56),
                      child: FilledButton(
                        key: ForgotPasswordScreen.sendKey,
                        onPressed: _busy ? null : _sendCode,
                        child: _busy
                            ? busyIndicator
                            : const Text('Enviarme el código'),
                      ),
                    ),
                  ] else
                    Form(
                      key: _resetForm,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 14),
                          TextFormField(
                            key: ForgotPasswordScreen.codeFieldKey,
                            controller: _code,
                            enabled: !_busy,
                            keyboardType: TextInputType.number,
                            maxLength: 6,
                            autofillHints: const [AutofillHints.oneTimeCode],
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            decoration: const InputDecoration(
                              labelText: 'Código del correo',
                              counterText: '',
                              prefixIcon: Icon(Icons.pin_outlined),
                              border: OutlineInputBorder(),
                            ),
                            validator: AuthValidators.code,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            key: ForgotPasswordScreen.passwordFieldKey,
                            controller: _password,
                            enabled: !_busy,
                            obscureText: _obscure,
                            autofillHints: const [AutofillHints.newPassword],
                            decoration: InputDecoration(
                              labelText: 'Contraseña nueva',
                              helperText:
                                  '8 o más caracteres, con letras y números',
                              prefixIcon: const Icon(
                                Icons.lock_outline_rounded,
                              ),
                              border: const OutlineInputBorder(),
                              suffixIcon: IconButton(
                                tooltip: _obscure
                                    ? 'Mostrar contraseña'
                                    : 'Ocultar contraseña',
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                                icon: Icon(
                                  _obscure
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
                            key: ForgotPasswordScreen.confirmFieldKey,
                            controller: _confirm,
                            enabled: !_busy,
                            obscureText: _obscure,
                            decoration: const InputDecoration(
                              labelText: 'Repite la contraseña nueva',
                              prefixIcon: Icon(Icons.lock_outline_rounded),
                              border: OutlineInputBorder(),
                            ),
                            validator: AuthValidators.confirmPassword(
                              () => _password.text,
                            ),
                            onFieldSubmitted: (_) => _save(),
                          ),
                          const SizedBox(height: 20),
                          ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 56),
                            child: FilledButton(
                              key: ForgotPasswordScreen.saveKey,
                              onPressed: _busy ? null : _save,
                              child: _busy
                                  ? busyIndicator
                                  : const Text('Guardar y entrar'),
                            ),
                          ),
                          TextButton(
                            onPressed: _busy || _wait > 0 ? null : _sendCode,
                            child: Text(
                              _wait > 0
                                  ? 'Reenviar código en $_wait s'
                                  : 'Reenviar código',
                            ),
                          ),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => setState(() {
                                    _codeSent = false;
                                    _error = null;
                                  }),
                            child: const Text('Usar otro correo'),
                          ),
                          // Esperando el código: salida obvia aunque no llegue.
                          Center(
                            child: UnderlinedLink(
                              label: 'Volver a inicio de sesión',
                              onPressed: _busy
                                  ? null
                                  : () => Navigator.of(context).maybePop(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      key: ForgotPasswordScreen.messageKey,
                      style: texto.bodyMedium?.copyWith(color: esquema.error),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
