import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_barrio_app/core/ui_kit/app_theme.dart';
import 'package:mi_barrio_app/features/legal/legal_documents.dart';
import 'package:mi_barrio_app/features/legal/legal_screens.dart';
import 'package:mi_barrio_app/features/legal/markdown_view.dart';

/// Documentos legales dentro de la app: se leen sin internet y se ven bien.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('parseMarkdown', () {
    test('títulos, listas, citas, líneas y párrafos', () {
      final blocks = parseMarkdown('''
# Título
## Sección
### Sub

Un párrafo
que sigue.

- uno
1. primero
> **Ojo:** importante
---
''');
      expect(blocks.map((b) => b.kind), [
        MdKind.h1,
        MdKind.h2,
        MdKind.h3,
        MdKind.paragraph,
        MdKind.bullet,
        MdKind.numbered,
        MdKind.quote,
        MdKind.rule,
      ]);
      expect(blocks[3].text, 'Un párrafo que sigue.');
      expect(blocks[5].number, '1');
    });

    test('tablas: quita la fila separadora y la cabecera vacía', () {
      final table = parseMarkdown('''
| | |
| --- | --- |
| Titular | **NetSurex** |
| RUC | 123 |
''').single;
      expect(table.kind, MdKind.table);
      expect(table.rows, [
        ['Titular', '**NetSurex**'],
        ['RUC', '123'],
      ]);
    });

    test('enlaces: negrita, enlaces a otros documentos y saltos internos', () {
      final links = <String>[];
      final spans = inlineSpans(
        'Lee la [Política](politica_de_privacidad.md), el **índice** y [aquí](#seccion).',
        const TextStyle(),
        Colors.blue,
        links.add,
      );
      final text = spans.map((s) => s.toPlainText()).join();
      expect(text, 'Lee la Política, el índice y aquí.');
      final tappable = spans.whereType<TextSpan>().where(
        (s) => s.recognizer != null,
      );
      expect(tappable.length, 1, reason: '#seccion no es un enlace');
    });
  });

  test('fromLink encuentra el documento aunque venga con carpeta', () {
    expect(LegalDocument.fromLink('politica_de_uso.md'), LegalDocument.community);
    expect(
      LegalDocument.fromLink('legal/terminos_y_condiciones.md'),
      LegalDocument.terms,
    );
    expect(
      LegalDocument.fromLink('../manual_de_usuario.md'),
      LegalDocument.manual,
    );
    expect(LegalDocument.fromLink('https://osmfoundation.org'), isNull);
  });

  test('todos los documentos están en la app y no quedan datos por llenar', () async {
    for (final doc in [...LegalDocument.all, LegalDocument.manual]) {
      final text = await rootBundle.loadString(doc.assetPath);
      expect(text.trim(), isNotEmpty, reason: doc.file);
      expect(parseMarkdown(text), isNotEmpty, reason: doc.file);
      for (final placeholder in ['[NOMBRE', '[CORREO DE SOPORTE]', '[RUC']) {
        expect(text.contains(placeholder), isFalse, reason: '${doc.file}: $placeholder');
      }
    }
  });

  testWidgets('"Términos y privacidad" lista los documentos y abre uno', (tester) async {
    tester.view.physicalSize = const Size(412, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.day(), home: const LegalDocumentsScreen()),
    );
    for (final doc in LegalDocument.all) {
      expect(find.text(doc.title), findsOneWidget);
    }
    expect(find.text(LegalDocument.manual.title), findsOneWidget);
    expect(find.textContaining('Próximamente'), findsOneWidget);

    await tester.tap(find.text(LegalDocument.privacy.title));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    expect(find.byType(LegalDocumentScreen), findsOneWidget);
    expect(find.text('Política de Privacidad'), findsOneWidget, reason: 'título del documento');
  });
}
