import 'dart:convert';

import 'package:flutter/services.dart';

/// Groserías y discurso de odio → asteriscos ("p***").
///
/// Usa la MISMA lista que el servidor (assets/moderation/offensive_words.json,
/// copia de mi_barrio_backend/app/core/offensive_words.json). El servidor
/// censura siempre antes de guardar; aquí se hace mientras se escribe para
/// que el vecino vea al instante qué no se va a publicar.
class ContentFilter {
  ContentFilter._();

  static const assetPath = 'assets/moderation/offensive_words.json';

  static Set<String> _words = const {};
  static List<List<String>> _phrases = const [];

  static bool get isLoaded => _words.isNotEmpty;

  /// Se llama una vez al abrir la app. Si falla, la app sigue (el servidor
  /// censura igual).
  static Future<void> load() async {
    try {
      loadFromJson(await rootBundle.loadString(assetPath));
    } catch (_) {}
  }

  static void loadFromJson(String source) {
    final data = jsonDecode(source) as Map<String, dynamic>;
    _words = {for (final w in data['words'] as List) normalize(w as String)};
    _phrases = [
      for (final p in data['hate_phrases'] as List)
        [for (final part in (p as String).split(' ')) normalize(part)],
    ];
  }

  static const _accents = {
    'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a', 'é': 'e', 'è': 'e', 'ë': 'e',
    'ê': 'e', 'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i', 'ó': 'o', 'ò': 'o',
    'ö': 'o', 'ô': 'o', 'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u', 'ñ': 'n',
  };
  static const _leet = {
    '4': 'a', '@': 'a', '3': 'e', '1': 'i', '!': 'i', '0': 'o', '5': 's',
    r'$': 's', '7': 't',
  };
  static final _token = RegExp(r'[\p{L}\p{N}_@$!]+', unicode: true);
  static final _notLetter = RegExp('[^a-z ]');
  static final _repeats = RegExp(r'(.)\1+');

  /// Igual que en el servidor: minúsculas, sin tildes, 4→a…, sin repetidas.
  static String normalize(String word) {
    final buffer = StringBuffer();
    for (final char in word.toLowerCase().split('')) {
      buffer.write(_accents[char] ?? _leet[char] ?? char);
    }
    return buffer
        .toString()
        .replaceAll(_notLetter, '')
        .replaceAllMapped(_repeats, (m) => m[1]!);
  }

  static String _mask(String token) =>
      token[0] + '*' * (token.length - 1);

  /// Índices (en [matches]) de las palabras ofensivas.
  static Set<int> _flagged(List<String> normalized) {
    final flagged = <int>{
      for (var i = 0; i < normalized.length; i++)
        if (_words.contains(normalized[i])) i,
    };
    for (final phrase in _phrases) {
      for (var start = 0; start + phrase.length <= normalized.length; start++) {
        var same = true;
        for (var k = 0; k < phrase.length && same; k++) {
          same = normalized[start + k] == phrase[k];
        }
        if (same) {
          for (var k = 0; k < phrase.length; k++) {
            flagged.add(start + k);
          }
        }
      }
    }
    return flagged;
  }

  /// [onlyFinishedWords]: mientras se escribe, la última palabra puede estar
  /// a medias ("put" → "putamente"…), así que no se toca hasta que termine.
  static String censor(String text, {bool onlyFinishedWords = false}) {
    if (text.isEmpty || !isLoaded) return text;
    final matches = _token.allMatches(text).toList();
    final flagged = _flagged([for (final m in matches) normalize(m[0]!)]);
    if (flagged.isEmpty) return text;
    final out = StringBuffer();
    var last = 0;
    for (var i = 0; i < matches.length; i++) {
      final m = matches[i];
      final unfinished = onlyFinishedWords && m.end == text.length;
      if (!flagged.contains(i) || unfinished) continue;
      out
        ..write(text.substring(last, m.start))
        ..write(_mask(m[0]!));
      last = m.end;
    }
    out.write(text.substring(last));
    return out.toString();
  }

  static bool isOffensive(String? text) =>
      text != null && text.isNotEmpty && censor(text) != text;
}

/// Para los campos donde se escribe algo que verán otros vecinos: al terminar
/// cada palabra ofensiva la cambia por asteriscos.
class OffensiveWordsFormatter extends TextInputFormatter {
  const OffensiveWordsFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final censored = ContentFilter.censor(
      newValue.text,
      onlyFinishedWords: true,
    );
    if (censored == newValue.text) return newValue;
    // El largo no cambia (cada letra pasa a "*"), el cursor queda igual.
    return newValue.copyWith(text: censored);
  }
}
