import 'package:url_launcher/url_launcher.dart';

/// Abre el marcador del teléfono o WhatsApp con un número del barrio.
///
/// Los números peruanos de 9 dígitos sin código de país se completan con +51
/// (WhatsApp exige el número internacional).
class ContactLauncher {
  ContactLauncher._();

  static const defaultCountryCode = '51';

  /// Solo los dígitos (y un "+" inicial si lo había).
  static String normalize(String raw) {
    final trimmed = raw.trim();
    final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    return trimmed.startsWith('+') ? '+$digits' : digits;
  }

  /// Número internacional sin "+", como lo pide wa.me: 51987654321.
  static String international(String raw) {
    final n = normalize(raw);
    if (n.startsWith('+')) return n.substring(1);
    if (n.startsWith('00')) return n.substring(2);
    if (n.length == 9) return '$defaultCountryCode$n'; // celular peruano
    return n;
  }

  static bool isDialable(String? raw) => raw != null && normalize(raw).replaceAll('+', '').length >= 3;

  static Uri telUri(String raw) => Uri(scheme: 'tel', path: normalize(raw));

  static Uri whatsappUri(String raw, {String? text}) => Uri.https(
        'wa.me',
        '/${international(raw)}',
        text == null || text.isEmpty ? null : {'text': text},
      );

  /// Abre el marcador. Devuelve false si el teléfono no pudo (ej. tablet sin SIM).
  static Future<bool> call(String raw) => _open(telUri(raw));

  /// Abre WhatsApp (o el navegador si no está instalado).
  static Future<bool> whatsapp(String raw, {String? text}) =>
      _open(whatsappUri(raw, text: text));

  static Future<bool> _open(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}
