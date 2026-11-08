import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/user_entity.dart';
import '../providers/auth_provider.dart';
import '../widgets/account_widgets.dart';
import '../widgets/auth_validators.dart';

/// Después de registrarse (o entrar por primera vez) con Google, el vecino
/// crea una contraseña. Así también puede entrar con correo y contraseña si
/// pierde el acceso a Google o usa otro teléfono.
///
/// Si no hay internet se puede dejar para después: en una emergencia nadie
/// debe quedar bloqueado fuera de la app. Se vuelve a pedir al abrirla.
class CreatePasswordScreen extends ConsumerStatefulWidget {
  const CreatePasswordScreen({super.key, required this.user, this.onSkip});

  final UserEntity user;

  /// "Hacerlo después" (solo aparece si falló por falta de conexión).
  final VoidCallback? onSkip;

  static const passwordFieldKey = ValueKey('create_password');
  static const confirmFieldKey = ValueKey('create_password_confirm');
  static const saveKey = ValueKey('create_password_save');
  static const skipKey = ValueKey('create_password_skip');
  static const messageKey = ValueKey('create_password_message');

  @override
  ConsumerState<CreatePasswordScreen> createState() =>
      _CreatePasswordScreenState();
}

class _CreatePasswordScreenState extends ConsumerState<CreatePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  bool _submitted = false;
  String? _error;

  /// Falló por conexión: se ofrece "Hacerlo después".
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    _password.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  static bool _looksOffline(String message) {
    final text = message.toLowerCase();
    return text.contains('internet') ||
        text.contains('conectar') ||
        text.contains('tardó demasiado') ||
        text.contains('despertando');
  }

  Future<void> _save() async {
    setState(() => _submitted = true);
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await ref
        .read(authProvider.notifier)
        .createPassword(_password.text);
    if (!mounted) return;
    if (error == null) {
      // La app sigue sola (el usuario ya tiene contraseña).
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text(
            'Listo: ya puedes entrar con Google o con tu correo y contraseña.',
          ),
        ),
      );
      return;
    }
    setState(() {
      _busy = false;
      _error = error;
      _offline = _looksOffline(error);
    });
  }

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    final esquema = Theme.of(context).colorScheme;
    final email = widget.user.email ?? 'tu correo';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Crea tu contraseña'),
        leading: AuthBackButton(
          tooltip: 'Salir',
          onPressed: _busy
              ? null
              : () => ref.read(authProvider.notifier).logout(),
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
              child: AutofillGroup(
                child: Form(
                  key: _formKey,
                  autovalidateMode: _submitted
                      ? AutovalidateMode.onUserInteraction
                      : AutovalidateMode.disabled,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Icon(
                        Icons.lock_person_rounded,
                        size: 56,
                        color: esquema.primary,
                      ),
                      const SizedBox(height: 12),
                      Semantics(
                        header: true,
                        child: Text(
                          'Último paso: tu contraseña',
                          style: texto.headlineSmall,
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text.rich(
                        TextSpan(
                          text: 'Entraste con Google como ',
                          children: [
                            TextSpan(
                              text: email,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const TextSpan(
                              text:
                                  '. Crea una contraseña para poder entrar '
                                  'también sin Google o desde otro teléfono.',
                            ),
                          ],
                        ),
                        textAlign: TextAlign.center,
                        style: texto.bodyLarge,
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        key: CreatePasswordScreen.passwordFieldKey,
                        controller: _password,
                        enabled: !_busy,
                        obscureText: _obscure,
                        autofocus: true,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        enableSuggestions: false,
                        autofillHints: const [AutofillHints.newPassword],
                        style: texto.bodyLarge,
                        decoration: InputDecoration(
                          labelText: 'Contraseña nueva',
                          helperText:
                              '8 o más caracteres, con letras y números',
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
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
                      const SizedBox(height: 8),
                      PasswordStrengthMeter(password: _password.text),
                      const SizedBox(height: 16),
                      TextFormField(
                        key: CreatePasswordScreen.confirmFieldKey,
                        controller: _confirm,
                        enabled: !_busy,
                        obscureText: _obscure,
                        textInputAction: TextInputAction.done,
                        autocorrect: false,
                        enableSuggestions: false,
                        style: texto.bodyLarge,
                        decoration: const InputDecoration(
                          labelText: 'Repite la contraseña',
                          prefixIcon: Icon(Icons.lock_outline_rounded),
                          border: OutlineInputBorder(),
                        ),
                        validator: AuthValidators.confirmPassword(
                          () => _password.text,
                        ),
                        onFieldSubmitted: (_) => _save(),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            _error!,
                            key: CreatePasswordScreen.messageKey,
                            textAlign: TextAlign.center,
                            style: texto.bodyMedium?.copyWith(
                              color: esquema.error,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 56),
                        child: FilledButton(
                          key: CreatePasswordScreen.saveKey,
                          onPressed: _busy ? null : _save,
                          child: _busy
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                  ),
                                )
                              : const Text('Guardar y entrar'),
                        ),
                      ),
                      if (_offline && widget.onSkip != null) ...[
                        const SizedBox(height: 8),
                        TextButton(
                          key: CreatePasswordScreen.skipKey,
                          onPressed: _busy ? null : widget.onSkip,
                          child: const Text('Sin señal: hacerlo después'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
