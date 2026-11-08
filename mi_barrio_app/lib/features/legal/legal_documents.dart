import 'package:flutter/material.dart';

/// Documentos legales y de ayuda que se ven dentro de la app.
///
/// Los .md viven en `assets/legal/` y son copia de `docs/legal/` y
/// `docs/manual_de_usuario.md`: si se cambia un documento, copiarlo también aquí.
class LegalDocument {
  const LegalDocument({
    required this.file,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  /// Nombre del archivo (también se usa para abrir enlaces entre documentos).
  final String file;
  final String title;
  final String subtitle;
  final IconData icon;

  String get assetPath => 'assets/legal/$file';

  static const terms = LegalDocument(
    file: 'terminos_y_condiciones.md',
    title: 'Términos y condiciones',
    subtitle: 'Las reglas para usar Mi Barrio',
    icon: Icons.gavel_rounded,
  );

  static const privacy = LegalDocument(
    file: 'politica_de_privacidad.md',
    title: 'Política de privacidad',
    subtitle: 'Qué datos usamos y tus derechos',
    icon: Icons.privacy_tip_outlined,
  );

  static const dataUse = LegalDocument(
    file: 'terminos_de_uso_de_informacion.md',
    title: 'Uso de la información',
    subtitle: 'Tu consentimiento y cómo cuidar los datos de otros',
    icon: Icons.fact_check_outlined,
  );

  static const community = LegalDocument(
    file: 'politica_de_uso.md',
    title: 'Normas de la comunidad',
    subtitle: 'Qué está prohibido, reportes y sanciones',
    icon: Icons.groups_rounded,
  );

  static const cookies = LegalDocument(
    file: 'politica_de_cookies.md',
    title: 'Cookies y almacenamiento',
    subtitle: 'Qué se guarda en tu celular',
    icon: Icons.storage_rounded,
  );

  static const eula = LegalDocument(
    file: 'eula.md',
    title: 'Licencia de uso (EULA)',
    subtitle: 'Qué puedes hacer con la app',
    icon: Icons.description_outlined,
  );

  static const legalNotice = LegalDocument(
    file: 'aviso_legal.md',
    title: 'Aviso legal',
    subtitle: 'Quiénes somos y cómo contactarnos',
    icon: Icons.info_outline_rounded,
  );

  static const manual = LegalDocument(
    file: 'manual_de_usuario.md',
    title: 'Manual de usuario',
    subtitle: 'Cómo usar cada parte de la app',
    icon: Icons.menu_book_rounded,
  );

  /// Orden en la pantalla "Términos y privacidad".
  static const all = [
    terms,
    privacy,
    dataUse,
    community,
    cookies,
    eula,
    legalNotice,
  ];

  /// Documento al que apunta un enlace como `politica_de_uso.md` o
  /// `legal/politica_de_uso.md`. null si no es uno de los nuestros.
  static LegalDocument? fromLink(String link) {
    final name = link.split('#').first.split('/').last;
    for (final doc in [...all, manual]) {
      if (doc.file == name) return doc;
    }
    return null;
  }
}
