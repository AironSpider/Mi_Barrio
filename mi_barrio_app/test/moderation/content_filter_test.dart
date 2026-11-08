import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_barrio_app/core/moderation/content_filter.dart';

void main() {
  setUpAll(() {
    ContentFilter.loadFromJson(
      File('assets/moderation/offensive_words.json').readAsStringSync(),
    );
  });

  test('la lista de la app es idéntica a la del servidor', () {
    final backend = File(
      '../mi_barrio_backend/app/core/offensive_words.json',
    );
    if (!backend.existsSync()) return; // fuera del monorepo
    expect(
      File('assets/moderation/offensive_words.json').readAsStringSync(),
      backend.readAsStringSync(),
      reason: 'Copia mi_barrio_backend/app/core/offensive_words.json a assets/moderation/',
    );
  });

  test('censura groserías con tildes, mayúsculas, números y letras repetidas', () {
    expect(ContentFilter.censor('Eres un HUEVÓN y un c0judo'), 'Eres un H***** y un c*****');
    expect(ContentFilter.censor('puuuuta madre'), 'p****** madre');
    expect(ContentFilter.censor('CTM ya llegó el agua'), 'C** ya llegó el agua');
  });

  test('censura frases de odio o violencia completas', () {
    expect(
      ContentFilter.censor('hay que matar a los venecos'),
      'h** q** m**** a los v******',
    );
    expect(ContentFilter.censor('hijo de puta'), 'h*** d* p***');
  });

  test('no toca palabras normales que se parecen', () {
    for (final ok in [
      'Necesito una escalera, gracias vecino',
      'Computadora y cálculo en Putina',
      'Vendo carro rojo',
      'Gil Pérez, gasfitero',
      'Disputa por el agua',
    ]) {
      expect(ContentFilter.censor(ok), ok, reason: ok);
    }
  });

  test('al escribir, espera a que termine la palabra', () {
    const formatter = OffensiveWordsFormatter();
    TextEditingValue type(String text) => formatter.formatEditUpdate(
      TextEditingValue.empty,
      TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length)),
    );
    expect(type('qué put').text, 'qué put');
    expect(type('qué puta ').text, 'qué p*** ');
    expect(type('qué puta ').selection.baseOffset, 'qué puta '.length);

    // Frase de odio escrita palabra por palabra (como en un celular real):
    // "hay que" no se tapa antes de tiempo y al final se tapa completa.
    var text = '';
    for (final word in ['Gracias', 'hay', 'que', 'matar', 'a', 'los', 'venecos']) {
      for (final char in '$word '.split('')) {
        text = type(text + char).text;
      }
    }
    expect(text, 'Gracias h** q** m**** a los v****** ');
  });
}
