import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/ui_kit/app_theme.dart';
import '../../data/datasources/auth_remote_datasource.dart';
import '../../data/datasources/google_sign_in_client.dart';
import '../../domain/entities/user_entity.dart';
import '../providers/auth_provider.dart';
import 'auth_validators.dart';

/// Botón "Continuar con Google" (blanco, con la G de colores, como pide Google).
class GoogleSignInButton extends StatelessWidget {
  const GoogleSignInButton({
    super.key,
    required this.onPressed,
    this.label = 'Continuar con Google',
    this.busy = false,
  });

  static const buttonKey = ValueKey('google_sign_in_button');

  final VoidCallback? onPressed;
  final String label;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: OutlinedButton(
        key: buttonKey,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: AppPalette.textPrimary,
          side: const BorderSide(color: Color(0xFF747775)),
        ),
        onPressed: busy ? null : onPressed,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (busy)
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            else
              const _GoogleG(),
            const SizedBox(width: 12),
            Flexible(child: Text(label, textAlign: TextAlign.center)),
          ],
        ),
      ),
    );
  }
}

/// Logo oficial de Google ("G" de 4 colores), como pide su guía de marca.
class _GoogleG extends StatelessWidget {
  const _GoogleG();

  static const _svg =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48">'
      '<path fill="#EA4335" d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z"/>'
      '<path fill="#4285F4" d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z"/>'
      '<path fill="#FBBC05" d="M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z"/>'
      '<path fill="#34A853" d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z"/>'
      '</svg>';

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SvgPicture.string(_svg, width: 22, height: 22),
    );
  }
}

/// Separador "o" entre el formulario y el botón de Google.
class OrDivider extends StatelessWidget {
  const OrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outlineVariant;
    return Row(
      children: [
        Expanded(child: Divider(color: color)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text('o', style: Theme.of(context).textTheme.bodyMedium),
        ),
        Expanded(child: Divider(color: color)),
      ],
    );
  }
}

/// Barra de fuerza de la contraseña: Débil / Regular / Buena / Fuerte.
class PasswordStrengthMeter extends StatelessWidget {
  const PasswordStrengthMeter({super.key, required this.password});

  static const meterKey = ValueKey('password_strength');

  final String password;

  @override
  Widget build(BuildContext context) {
    final score = AuthValidators.strength(password);
    if (score == 0) return const SizedBox.shrink();
    final color = switch (score) {
      1 => AppPalette.syncFailed,
      2 => AppPalette.urgencyHigh,
      3 => AppPalette.daySecondary,
      _ => AppPalette.syncSynced,
    };
    final label = AuthValidators.strengthLabel(score);
    return Semantics(
      key: meterKey,
      label: 'Seguridad de la contraseña: $label',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          children: [
            for (var i = 1; i <= 4; i++) ...[
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 6,
                  decoration: BoxDecoration(
                    color: i <= score ? color : AppPalette.pendingBackground,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              if (i < 4) const SizedBox(width: 4),
            ],
            const SizedBox(width: 10),
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tarjeta grande y tocable para elegir el tipo de cuenta (en vez de un
/// desplegable): se entiende sin leer mucho y es fácil de tocar.
class RoleCard extends StatelessWidget {
  const RoleCard({
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

/// Las dos tarjetas: vecino o comerciante.
class RoleChoice extends StatelessWidget {
  const RoleChoice({
    super.key,
    required this.role,
    required this.onChanged,
    this.vecinoKey,
    this.comercianteKey,
  });

  final UserRole role;
  final ValueChanged<UserRole>? onChanged;
  final Key? vecinoKey;
  final Key? comercianteKey;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RoleCard(
          key: vecinoKey,
          icon: Icons.home_rounded,
          title: 'Soy vecino',
          subtitle: 'Pido y ofrezco ayuda, y encuentro oficios.',
          selected: role == UserRole.vecino,
          onTap: onChanged == null ? null : () => onChanged!(UserRole.vecino),
        ),
        const SizedBox(height: 10),
        RoleCard(
          key: comercianteKey,
          icon: Icons.storefront_rounded,
          title: 'Tengo un oficio o negocio',
          subtitle: 'Ofrezco mis servicios a mis vecinos.',
          selected: role == UserRole.comerciante,
          onTap: onChanged == null
              ? null
              : () => onChanged!(UserRole.comerciante),
        ),
      ],
    );
  }
}

/// Lo que eligió el vecino al entrar con Google por primera vez.
class NeighborhoodChoice {
  const NeighborhoodChoice(this.joinCode, this.role);
  final String joinCode;
  final UserRole role;
}

/// Hoja que aparece la PRIMERA vez que alguien entra con Google: falta saber
/// a qué barrio pertenece y cómo va a usar la app.
Future<NeighborhoodChoice?> askNeighborhood(BuildContext context) {
  return showModalBottomSheet<NeighborhoodChoice>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _NeighborhoodSheet(),
  );
}

class _NeighborhoodSheet extends StatefulWidget {
  const _NeighborhoodSheet();

  static const codeFieldKey = ValueKey('google_join_code');
  static const continueKey = ValueKey('google_join_continue');

  @override
  State<_NeighborhoodSheet> createState() => _NeighborhoodSheetState();
}

class _NeighborhoodSheetState extends State<_NeighborhoodSheet> {
  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();
  UserRole _role = UserRole.vecino;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _continue() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context)
        .pop(NeighborhoodChoice(_code.text.trim().toUpperCase(), _role));
  }

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        0,
        24,
        24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Un paso más', style: texto.headlineSmall),
              const SizedBox(height: 4),
              Text(
                'Es tu primera vez con Google en Mi Barrio. Escribe el código de tu '
                'barrio (te lo da tu junta vecinal).',
                style: texto.bodyMedium,
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: _NeighborhoodSheet.codeFieldKey,
                controller: _code,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Código de tu barrio',
                  hintText: 'Ej: BARRIO-01',
                  prefixIcon: Icon(Icons.vpn_key_outlined),
                  border: OutlineInputBorder(),
                ),
                validator: AuthValidators.joinCode,
              ),
              const SizedBox(height: 16),
              Text('¿Cómo vas a usar Mi Barrio?', style: texto.titleMedium),
              const SizedBox(height: 8),
              RoleChoice(
                role: _role,
                onChanged: (r) => setState(() => _role = r),
              ),
              const SizedBox(height: 20),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: FilledButton(
                  key: _NeighborhoodSheet.continueKey,
                  onPressed: _continue,
                  child: const Text('Entrar a mi barrio'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Flujo completo de "Continuar con Google" desde el login o el registro.
///
/// [joinCode]/[role] llegan desde el registro (ya escritos en el formulario);
/// desde el login van null y, si la cuenta es nueva, se piden en una hoja.
/// Devuelve null si entró (o el vecino canceló) o el mensaje de error a mostrar.
Future<String?> continueWithGoogle(
  BuildContext context,
  WidgetRef ref, {
  String? joinCode,
  UserRole role = UserRole.vecino,
}) async {
  final source = ref.read(googleIdTokenSourceProvider);
  final notifier = ref.read(authProvider.notifier);
  if (!source.isAvailable) {
    return 'Entrar con Google funciona en la app del celular. En la computadora, '
        'usa tu correo y contraseña.';
  }
  String? idToken;
  try {
    idToken = await source.getIdToken();
  } on AuthException catch (error) {
    return error.message;
  }
  if (idToken == null) return null; // cerró la ventana de Google

  var result = await notifier.signInWithGoogle(
    idToken: idToken,
    joinCode: joinCode,
    role: role,
  );
  if (result.outcome == GoogleSignInOutcome.needsNeighborhood) {
    if (!context.mounted) return null;
    final choice = await askNeighborhood(context);
    if (choice == null) {
      await source.signOut();
      return null;
    }
    result = await notifier.signInWithGoogle(
      idToken: idToken,
      joinCode: choice.joinCode,
      role: choice.role,
    );
  }
  return switch (result.outcome) {
    GoogleSignInOutcome.signedIn => null,
    GoogleSignInOutcome.needsNeighborhood => 'Falta el código de tu barrio.',
    GoogleSignInOutcome.failed =>
      result.message ?? 'No se pudo entrar con Google.',
  };
}
