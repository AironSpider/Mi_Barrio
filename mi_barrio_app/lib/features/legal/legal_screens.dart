import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'legal_documents.dart';
import 'markdown_view.dart';

/// Abre un documento (no necesita sesión: se usa también en el registro).
Future<void> openLegalDocument(BuildContext context, LegalDocument doc) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LegalDocumentScreen(document: doc),
      ),
    );

/// Lista "Términos y privacidad" (desde la pestaña "Tú").
class LegalDocumentsScreen extends StatelessWidget {
  const LegalDocumentsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Términos y privacidad')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
            child: Text(
              'Aquí están las reglas de Mi Barrio y cómo cuidamos tus datos. '
              'Puedes leerlos cuando quieras, también sin internet.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < LegalDocument.all.length; i++) ...[
                  if (i > 0)
                    const Divider(height: 1, indent: 16, endIndent: 16),
                  _DocTile(doc: LegalDocument.all[i]),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            clipBehavior: Clip.antiAlias,
            child: _DocTile(doc: LegalDocument.manual),
          ),
          const SizedBox(height: 16),
          Card(
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              minTileHeight: 64,
              leading: const Icon(Icons.public_rounded),
              title: const Text('Versión web de la política de privacidad'),
              subtitle: const Text(
                'Próximamente, cuando Mi Barrio esté en Google Play',
              ),
              enabled: false,
            ),
          ),
        ],
      ),
    );
  }
}

class _DocTile extends StatelessWidget {
  const _DocTile({required this.doc});

  final LegalDocument doc;

  @override
  Widget build(BuildContext context) => ListTile(
    key: ValueKey('legal_${doc.file}'),
    minTileHeight: 64,
    leading: Icon(doc.icon, color: Theme.of(context).colorScheme.primary),
    title: Text(doc.title),
    subtitle: Text(doc.subtitle),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: () => openLegalDocument(context, doc),
  );
}

/// Un documento, leído de los assets de la app (funciona sin internet).
class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({super.key, required this.document, this.bundle});

  final LegalDocument document;

  /// Reemplazable en pruebas.
  final AssetBundle? bundle;

  Future<void> _openLink(BuildContext context, String target) async {
    final doc = LegalDocument.fromLink(target);
    if (doc != null) {
      await openLegalDocument(context, doc);
      return;
    }
    final uri = Uri.tryParse(
      target.contains('@') && !target.contains(':') ? 'mailto:$target' : target,
    );
    if (uri == null || !uri.hasScheme) return;
    final opened = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    ).catchError((_) => false);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('No se pudo abrir $target')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(document.title)),
      body: FutureBuilder<String>(
        future: (bundle ?? rootBundle).loadString(document.assetPath),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('No se pudo abrir este documento.'),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return MarkdownView(
            data: snapshot.data!,
            onLink: (target) => _openLink(context, target),
          );
        },
      ),
    );
  }
}

/// "Al crear tu cuenta aceptas los Términos y la Política de privacidad."
/// Con enlaces que abren cada documento. Se muestra en registro y login.
class LegalConsentText extends StatefulWidget {
  const LegalConsentText({
    super.key,
    this.prefix = 'Al crear tu cuenta aceptas los ',
    this.alignStart = false,
  });

  final String prefix;

  /// true dentro de la casilla de aceptación (texto a la izquierda).
  final bool alignStart;

  @override
  State<LegalConsentText> createState() => _LegalConsentTextState();
}

class _LegalConsentTextState extends State<LegalConsentText> {
  late final _terms = TapGestureRecognizer()
    ..onTap = () => openLegalDocument(context, LegalDocument.terms);
  late final _privacy = TapGestureRecognizer()
    ..onTap = () => openLegalDocument(context, LegalDocument.privacy);
  late final _community = TapGestureRecognizer()
    ..onTap = () => openLegalDocument(context, LegalDocument.community);

  @override
  void dispose() {
    _terms.dispose();
    _privacy.dispose();
    _community.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodySmall!.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      height: 1.4,
    );
    final link = base.copyWith(
      color: theme.colorScheme.primary,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
      decorationColor: theme.colorScheme.primary,
    );
    return Text.rich(
      key: const ValueKey('legal_consent_text'),
      textAlign: widget.alignStart ? TextAlign.start : TextAlign.center,
      TextSpan(
        style: base,
        children: [
          TextSpan(text: widget.prefix),
          TextSpan(
            text: 'Términos y condiciones',
            style: link,
            recognizer: _terms,
          ),
          const TextSpan(text: ', la '),
          TextSpan(
            text: 'Política de privacidad',
            style: link,
            recognizer: _privacy,
          ),
          const TextSpan(text: ' y las '),
          TextSpan(
            text: 'Normas de la comunidad',
            style: link,
            recognizer: _community,
          ),
          const TextSpan(text: '.'),
        ],
      ),
    );
  }
}

/// Casilla OBLIGATORIA para crear una cuenta: "Acepto los Términos…".
///
/// Es un campo del formulario: si no está marcada, "Crear cuenta" muestra el
/// error debajo y el lector de pantalla lo anuncia. Los enlaces abren cada
/// documento sin marcar la casilla (se pueden leer antes de aceptar).
class TermsAcceptanceField extends FormField<bool> {
  TermsAcceptanceField({
    super.key,
    super.enabled,
    ValueChanged<bool>? onChanged,
  }) : super(
         initialValue: false,
         validator: (value) => value == true ? null : missingMessage,
         builder: (field) => _TermsAcceptanceBody(
           field: field,
           enabled: field.widget.enabled,
           onChanged: onChanged,
         ),
       );

  static const checkboxKey = ValueKey('terms_checkbox');
  static const missingMessage =
      'Para crear tu cuenta, marca que aceptas los Términos y condiciones.';
}

class _TermsAcceptanceBody extends StatelessWidget {
  const _TermsAcceptanceBody({
    required this.field,
    required this.enabled,
    this.onChanged,
  });

  final FormFieldState<bool> field;
  final bool enabled;
  final ValueChanged<bool>? onChanged;

  void _toggle() {
    final next = !(field.value ?? false);
    field.didChange(next);
    // Si ya mostraba "marca que aceptas…", el error se va al marcarla.
    if (field.hasError) field.validate();
    onChanged?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = field.errorText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: error != null
                  ? theme.colorScheme.error
                  : theme.colorScheme.outlineVariant,
              width: error != null ? 2 : 1,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(4, 4, 12, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Área táctil de 48 px y una etiqueta completa para el lector.
              Semantics(
                label: 'Acepto los Términos y condiciones, la Política de '
                    'privacidad y las Normas de la comunidad',
                hint: 'Obligatorio para crear la cuenta',
                child: Checkbox(
                  key: TermsAcceptanceField.checkboxKey,
                  value: field.value ?? false,
                  onChanged: enabled ? (_) => _toggle() : null,
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                ),
              ),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  // Para el lector de pantalla la casilla ya se marca sola
                  // (con su etiqueta); aquí solo se anuncian los enlaces.
                  excludeFromSemantics: true,
                  onTap: enabled ? _toggle : null,
                  // El lector ya leyó la casilla; aquí solo quedan los enlaces.
                  child: const LegalConsentText(
                    prefix: 'Acepto los ',
                    alignStart: true,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 12),
            child: Semantics(
              liveRegion: true,
              child: Text(
                error,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
