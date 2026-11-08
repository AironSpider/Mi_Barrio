import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/user_entity.dart';
import '../../data/datasources/auth_remote_datasource.dart';
import '../../../../core/auth/auth_session_store.dart';
import '../providers/auth_provider.dart';
import '../register_draft.dart';
import '../widgets/account_widgets.dart';
import '../widgets/auth_validators.dart';

/// Aparece después de crear una cuenta con contraseña: hay que escribir el
/// código de 6 dígitos que llegó al correo antes de usar la app.
class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key, required this.user});

  final UserEntity user;

  static const codeFieldKey = ValueKey('verify_code');
  static const submitKey = ValueKey('verify_submit');
  static const resendKey = ValueKey('verify_resend');
  static const messageKey = ValueKey('verify_message');
  static const backLinkKey = ValueKey('verify_back_link');

  /// Espera entre reenvíos (igual que el servidor).
  static const resendAfter = Duration(seconds: 60);

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen> {
  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _info;
  int _wait = VerifyEmailScreen.resendAfter.inSeconds;
  Timer? _timer;

  /// true = llegó aquí creando la cuenta ("Volver para cambiar datos");
  /// false = iniciando sesión ("Volver a inicio de sesión").
  bool _fromRegister = false;

  @override
  void initState() {
    super.initState();
    _startCountdown(); // el servidor acaba de enviar el primer código
    RegisterDraft.load().then((draft) {
      final email = widget.user.email?.trim().toLowerCase();
      if (!mounted || draft == null || email == null) return;
      setState(() => _fromRegister = draft.email.trim().toLowerCase() == email);
    });
  }

  /// Sale de esta pantalla aunque el código nunca llegue (antes se quedaba
  /// atrapado aquí, incluso al cerrar y abrir la app).
  Future<void> _goBack() async {
    if (_busy) return;
    setState(() => _busy = true);
    if (_fromRegister) {
      // La cuenta sin confirmar se borra para poder registrarse de nuevo
      // (con el mismo u otro correo). Sin red, registrarse otra vez igual
      // reemplaza sus datos.
      final token = AuthSessionStore.instance.token;
      if (token != null) {
        try {
          await AuthRemoteDatasource().deleteUnverifiedAccount(token);
        } catch (_) {}
      }
      RegisterDraft.reopenRequested = true;
    } else {
      await RegisterDraft.clear();
    }
    await ref.read(authProvider.notifier).logout();
    // Si cerrar sesión falló, la pantalla sigue: se puede volver a intentar.
    if (mounted) setState(() => _busy = false);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _wait = VerifyEmailScreen.resendAfter.inSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _wait--);
      if (_wait <= 0) t.cancel();
    });
  }

  Future<void> _verify() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    final error = await ref
        .read(authProvider.notifier)
        .verifyEmail(_code.text.trim());
    if (error == null) await RegisterDraft.clear();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  Future<void> _resend() async {
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    final error = await ref
        .read(authProvider.notifier)
        .resendVerificationCode();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
      _info = error == null ? 'Listo: te enviamos un código nuevo.' : null;
    });
    if (error == null) _startCountdown();
  }

  String get _backLabel =>
      _fromRegister ? 'Volver para cambiar datos' : 'Volver a inicio de sesión';

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    final esquema = Theme.of(context).colorScheme;
    final email = widget.user.email ?? 'tu correo';
    return Scaffold(
      appBar: AppBar(
        title: const Text('Confirma tu correo'),
        leading: AuthBackButton(
          tooltip: _backLabel,
          onPressed: _busy ? null : _goBack,
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
                    Icon(
                      Icons.mark_email_unread_rounded,
                      size: 56,
                      color: esquema.primary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Revisa tu correo',
                      style: texto.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text.rich(
                      TextSpan(
                        text: 'Te enviamos un código de 6 números a ',
                        children: [
                          TextSpan(
                            text: email,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const TextSpan(
                            text: '. Escríbelo aquí para empezar.',
                          ),
                        ],
                      ),
                      textAlign: TextAlign.center,
                      style: texto.bodyLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Si no lo ves, busca en "Spam" o "Promociones".',
                      textAlign: TextAlign.center,
                      style: texto.bodyMedium?.copyWith(
                        color: esquema.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      key: VerifyEmailScreen.codeFieldKey,
                      controller: _code,
                      enabled: !_busy,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      maxLength: 6,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: texto.headlineMedium?.copyWith(letterSpacing: 12),
                      decoration: const InputDecoration(
                        counterText: '',
                        hintText: '······',
                        border: OutlineInputBorder(),
                      ),
                      validator: AuthValidators.code,
                      onChanged: (v) {
                        if (v.length == 6 && !_busy) _verify();
                      },
                    ),
                    if (_error != null || _info != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error ?? _info!,
                        key: VerifyEmailScreen.messageKey,
                        textAlign: TextAlign.center,
                        style: texto.bodyMedium?.copyWith(
                          color: _error != null
                              ? esquema.error
                              : esquema.primary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 56),
                      child: FilledButton(
                        key: VerifyEmailScreen.submitKey,
                        onPressed: _busy ? null : _verify,
                        child: _busy
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                ),
                              )
                            : const Text('Confirmar'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      key: VerifyEmailScreen.resendKey,
                      onPressed: _busy || _wait > 0 ? null : _resend,
                      child: Text(
                        _wait > 0
                            ? 'Reenviar código en $_wait s'
                            : 'Reenviar código',
                      ),
                    ),
                    const SizedBox(height: 4),
                    Center(
                      child: UnderlinedLink(
                        key: VerifyEmailScreen.backLinkKey,
                        label: _backLabel,
                        onPressed: _busy ? null : _goBack,
                      ),
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
