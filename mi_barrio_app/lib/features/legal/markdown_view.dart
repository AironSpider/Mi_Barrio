import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Muestra un Markdown sencillo (el de nuestros documentos) sin librerías extra.
///
/// Soporta: títulos (#, ##, ###), párrafos, listas (- y 1.), citas (>),
/// tablas (| a | b |), líneas (---), **negrita**, `código` y [enlaces](destino).
class MarkdownView extends StatelessWidget {
  const MarkdownView({
    super.key,
    required this.data,
    required this.onLink,
    this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 40),
  });

  final String data;

  /// Se llama al tocar un enlace con su destino (p. ej. "politica_de_uso.md").
  final void Function(String target) onLink;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final blocks = parseMarkdown(data);
    return ListView.builder(
      padding: padding,
      itemCount: blocks.length,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _BlockView(block: blocks[index], onLink: onLink),
      ),
    );
  }
}

/// Tipos de bloque que entiende [MarkdownView].
enum MdKind { h1, h2, h3, paragraph, bullet, numbered, quote, table, rule }

/// Un bloque del documento: título, párrafo, lista, cita, tabla o línea.
class MdBlock {
  MdBlock(this.kind, {this.text = '', this.rows = const [], this.number = ''});

  final MdKind kind;
  final String text;
  final List<List<String>> rows;
  final String number;
}

final _numbered = RegExp(r'^(\d+)\.\s+(.*)$');
final _tableSeparator = RegExp(r'^\|?\s*:?-{3,}');

/// Convierte el texto en bloques. Público para poder probarlo.
List<MdBlock> parseMarkdown(String source) {
  final lines = source.replaceAll('\r\n', '\n').split('\n');
  final blocks = <MdBlock>[];
  final paragraph = <String>[];

  void flushParagraph() {
    if (paragraph.isEmpty) return;
    blocks.add(MdBlock(MdKind.paragraph, text: paragraph.join(' ')));
    paragraph.clear();
  }

  var i = 0;
  while (i < lines.length) {
    final raw = lines[i];
    final line = raw.trim();
    if (line.isEmpty) {
      flushParagraph();
      i++;
      continue;
    }
    if (line.startsWith('|')) {
      flushParagraph();
      final rows = <List<String>>[];
      while (i < lines.length && lines[i].trim().startsWith('|')) {
        final row = lines[i].trim();
        if (!_tableSeparator.hasMatch(row)) {
          var cells = row.split('|');
          cells = cells.sublist(1, cells.length - (row.endsWith('|') ? 1 : 0));
          rows.add(cells.map((c) => c.trim()).toList());
        }
        i++;
      }
      // Una cabecera vacía ("| | |") no aporta nada.
      if (rows.isNotEmpty && rows.first.every((c) => c.isEmpty)) {
        rows.removeAt(0);
      }
      if (rows.isNotEmpty) blocks.add(MdBlock(MdKind.table, rows: rows));
      continue;
    }
    if (line == '---' || line == '***') {
      flushParagraph();
      blocks.add(MdBlock(MdKind.rule));
    } else if (line.startsWith('### ')) {
      flushParagraph();
      blocks.add(MdBlock(MdKind.h3, text: line.substring(4)));
    } else if (line.startsWith('## ')) {
      flushParagraph();
      blocks.add(MdBlock(MdKind.h2, text: line.substring(3)));
    } else if (line.startsWith('# ')) {
      flushParagraph();
      blocks.add(MdBlock(MdKind.h1, text: line.substring(2)));
    } else if (line.startsWith('>')) {
      flushParagraph();
      final quote = <String>[];
      while (i < lines.length && lines[i].trim().startsWith('>')) {
        quote.add(lines[i].trim().replaceFirst(RegExp(r'^>\s?'), ''));
        i++;
      }
      blocks.add(MdBlock(MdKind.quote, text: quote.join('\n')));
      continue;
    } else if (line.startsWith('- ') || line.startsWith('* ')) {
      flushParagraph();
      final indent = raw.length - raw.trimLeft().length;
      blocks.add(
        MdBlock(
          MdKind.bullet,
          text: line.substring(2),
          number: indent >= 2 ? '  ' : '',
        ),
      );
    } else if (_numbered.hasMatch(line)) {
      flushParagraph();
      final match = _numbered.firstMatch(line)!;
      blocks.add(
        MdBlock(
          MdKind.numbered,
          text: match.group(2)!,
          number: match.group(1)!,
        ),
      );
    } else {
      paragraph.add(line);
    }
    i++;
  }
  flushParagraph();
  return blocks;
}

final _inline = RegExp(r'\*\*(.+?)\*\*|`([^`]+)`|\[([^\]]+)\]\(([^)]+)\)');

/// Texto con **negrita**, `código` y [enlaces](destino).
List<InlineSpan> inlineSpans(
  String text,
  TextStyle base,
  Color linkColor,
  void Function(String target) onLink,
) {
  final spans = <InlineSpan>[];
  var last = 0;
  for (final m in _inline.allMatches(text)) {
    if (m.start > last) {
      spans.add(TextSpan(text: text.substring(last, m.start)));
    }
    if (m.group(1) != null) {
      spans.addAll(
        inlineSpans(m.group(1)!, base, linkColor, onLink).map((s) => _bold(s)),
      );
    } else if (m.group(2) != null) {
      spans.add(
        TextSpan(
          text: m.group(2),
          style: const TextStyle(fontFamily: 'monospace'),
        ),
      );
    } else {
      final target = m.group(4)!;
      // Los saltos dentro de la misma página (#seccion) se muestran como texto.
      if (target.startsWith('#')) {
        spans.add(TextSpan(text: m.group(3)));
      } else {
        spans.add(
          TextSpan(
            text: m.group(3),
            style: TextStyle(
              color: linkColor,
              decoration: TextDecoration.underline,
              decorationColor: linkColor,
            ),
            recognizer: TapGestureRecognizer()..onTap = () => onLink(target),
          ),
        );
      }
    }
    last = m.end;
  }
  if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
  return spans;
}

InlineSpan _bold(InlineSpan span) {
  if (span is! TextSpan) return span;
  return TextSpan(
    text: span.text,
    children: span.children,
    recognizer: span.recognizer,
    style: (span.style ?? const TextStyle()).copyWith(
      fontWeight: FontWeight.w700,
    ),
  );
}

class _BlockView extends StatelessWidget {
  const _BlockView({required this.block, required this.onLink});

  final MdBlock block;
  final void Function(String target) onLink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final body = theme.textTheme.bodyLarge!.copyWith(height: 1.45);

    Widget rich(String text, TextStyle style) => Text.rich(
      TextSpan(
        style: style,
        children: inlineSpans(text, style, scheme.primary, onLink),
      ),
    );

    switch (block.kind) {
      case MdKind.h1:
        return Semantics(
          header: true,
          child: rich(block.text, theme.textTheme.headlineSmall!),
        );
      case MdKind.h2:
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Semantics(
            header: true,
            child: rich(block.text, theme.textTheme.titleLarge!),
          ),
        );
      case MdKind.h3:
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Semantics(
            header: true,
            child: rich(block.text, theme.textTheme.titleMedium!),
          ),
        );
      case MdKind.paragraph:
        return rich(block.text, body);
      case MdKind.bullet:
        return Padding(
          padding: EdgeInsets.only(left: block.number.isEmpty ? 4 : 24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('•  ', style: body),
              Expanded(child: rich(block.text, body)),
            ],
          ),
        );
      case MdKind.numbered:
        return Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 26, child: Text('${block.number}.', style: body)),
              Expanded(child: rich(block.text, body)),
            ],
          ),
        );
      case MdKind.quote:
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.primaryContainer.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(12),
            border: Border(left: BorderSide(color: scheme.primary, width: 4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final line in block.text.split('\n'))
                if (line.trim().isNotEmpty) rich(line, body),
            ],
          ),
        );
      case MdKind.rule:
        return const Divider(height: 12);
      case MdKind.table:
        final small = theme.textTheme.bodyMedium!.copyWith(height: 1.35);
        final columns = block.rows
            .map((r) => r.length)
            .reduce((a, b) => a > b ? a : b);
        return ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Table(
            border: TableBorder.all(color: scheme.outlineVariant),
            defaultVerticalAlignment: TableCellVerticalAlignment.top,
            children: [
              for (var r = 0; r < block.rows.length; r++)
                TableRow(
                  decoration: r == 0 && block.rows.length > 1
                      ? BoxDecoration(color: scheme.surfaceContainerHighest)
                      : null,
                  children: [
                    for (var c = 0; c < columns; c++)
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: rich(
                          c < block.rows[r].length ? block.rows[r][c] : '',
                          r == 0 && block.rows.length > 1
                              ? small.copyWith(fontWeight: FontWeight.w700)
                              : small,
                        ),
                      ),
                  ],
                ),
            ],
          ),
        );
    }
  }
}
