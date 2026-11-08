import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../../core/ui_kit/app_theme.dart';
import '../data/content_reports.dart';
import '../../../core/moderation/content_filter.dart';

/// Lo que el vecino eligió o escribió (se conserva al tocar "Regresar").
class _ReportDraft {
  String? reason;
  String detail = '';
}

/// Botón 🚩 "Reportar" para el detalle de un favor o un servicio.
class ReportButton extends StatelessWidget {
  const ReportButton({
    super.key,
    required this.targetType,
    required this.targetId,
    this.onReported,
    this.datasource,
  });

  final String targetType;
  final String targetId;

  /// Se llama después de enviar el reporte (p. ej. para cerrar el detalle:
  /// quien reporta deja de ver la publicación).
  final VoidCallback? onReported;
  final ContentReportsDatasource? datasource;

  static const buttonKey = ValueKey('report_button');

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: buttonKey,
      tooltip: 'Reportar publicación',
      onPressed: () async {
        final sent = await showReportFlow(
          context,
          targetType: targetType,
          targetId: targetId,
          datasource: datasource,
        );
        if (sent) onReported?.call();
      },
      icon: const FaIcon(
        FontAwesomeIcons.solidFlag,
        size: 18,
        color: AppPalette.urgencyCritical,
      ),
    );
  }
}

/// Flujo de reporte: motivo → confirmación → listo. Cada modal se cierra
/// antes de abrir el siguiente (nunca quedan uno encima de otro).
/// Devuelve true si el reporte se guardó.
Future<bool> showReportFlow(
  BuildContext context, {
  required String targetType,
  required String targetId,
  ContentReportsDatasource? datasource,
}) async {
  final ds = datasource ?? ContentReportsDatasource();
  final messenger = ScaffoldMessenger.of(context);
  if (await ds.hasReported(targetId)) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Ya reportaste esta publicación. La estamos revisando.')),
      );
    return false;
  }
  if (!context.mounted) return false;

  final draft = _ReportDraft();
  while (true) {
    if (!context.mounted) return false;
    final next = await showDialog<bool>(
      context: context,
      builder: (_) => _ReasonDialog(draft: draft),
    );
    if (next != true || !context.mounted) return false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const _ConfirmDialog(),
    );
    if (!context.mounted) return false;
    if (confirmed != true) continue; // "Regresar": vuelve al motivo con lo elegido.

    try {
      await ds.report(
        targetType: targetType,
        targetId: targetId,
        reason: draft.reason!,
        detail: draft.reason == ReportReason.otro ? draft.detail : null,
      );
    } catch (_) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('No se pudo guardar el reporte. Intenta de nuevo.')),
        );
      return false;
    }
    if (!context.mounted) return true;
    await showDialog<void>(context: context, builder: (_) => const _DoneDialog());
    return true;
  }
}

class _DialogHeader extends StatelessWidget {
  const _DialogHeader({required this.title, this.onClose});

  final String title;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(title, style: Theme.of(context).textTheme.titleLarge),
          ),
        ),
        IconButton(
          tooltip: 'Cerrar',
          onPressed: onClose ?? () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded),
        ),
      ],
    );
  }
}

ButtonStyle _redButton() => FilledButton.styleFrom(
  backgroundColor: AppPalette.urgencyCritical,
  foregroundColor: Colors.white,
  disabledBackgroundColor: AppPalette.filterActiveBackground,
  minimumSize: const Size.fromHeight(48),
);

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.draft});

  final _ReportDraft draft;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  late final TextEditingController _detail = TextEditingController(
    text: widget.draft.detail,
  );

  @override
  void dispose() {
    _detail.dispose();
    super.dispose();
  }

  bool get _ready =>
      widget.draft.reason != null &&
      (widget.draft.reason != ReportReason.otro || _detail.text.trim().length >= 3);

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    return Dialog(
      backgroundColor: AppPalette.card,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 8, 0),
              child: _DialogHeader(
                title: 'Reportar publicación',
                onClose: () => Navigator.of(context).pop(false),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        'Si deseas reportar esta publicación, cuéntanos el motivo:',
                        style: texto.bodyLarge,
                      ),
                    ),
                    const SizedBox(height: 8),
                    RadioGroup<String>(
                      groupValue: widget.draft.reason,
                      onChanged: (v) => setState(() => widget.draft.reason = v),
                      child: Column(
                        children: [
                          for (final entry in ReportReason.labels.entries)
                            RadioListTile<String>(
                              key: ValueKey('report_reason_${entry.key}'),
                              value: entry.key,
                              title: Text(entry.value),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                            ),
                        ],
                      ),
                    ),
                    if (widget.draft.reason == ReportReason.otro)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                        child: TextField(
                          inputFormatters: const [OffensiveWordsFormatter()],
                          key: const ValueKey('report_detail'),
                          controller: _detail,
                          autofocus: true,
                          maxLength: ContentReportsDatasource.maxDetail,
                          minLines: 2,
                          maxLines: 4,
                          textCapitalization: TextCapitalization.sentences,
                          onChanged: (v) => setState(() => widget.draft.detail = v),
                          decoration: const InputDecoration(
                            labelText: 'Escribe el motivo',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: FilledButton(
                key: const ValueKey('report_send'),
                style: _redButton(),
                onPressed: _ready ? () => Navigator.of(context).pop(true) : null,
                child: const Text('Enviar reporte'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppPalette.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '¿Está seguro de reportar esta publicación?',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const ValueKey('report_back'),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: AppPalette.card,
                        foregroundColor: AppPalette.textPrimary,
                        side: const BorderSide(color: AppPalette.pillBorder),
                        minimumSize: const Size.fromHeight(48),
                      ),
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Regresar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('report_confirm'),
                      style: _redButton(),
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('Enviar reporte'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DoneDialog extends StatelessWidget {
  const _DoneDialog();

  @override
  Widget build(BuildContext context) {
    final colors = MiBarrioColors.of(context);
    final texto = Theme.of(context).textTheme;
    return Dialog(
      backgroundColor: AppPalette.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  tooltip: 'Cerrar',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
              Container(
                width: 72,
                height: 72,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: colors.accentSoft, shape: BoxShape.circle),
                child: FaIcon(FontAwesomeIcons.solidCircleCheck, size: 36, color: colors.brand),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Column(
                  children: [
                    Text(
                      'Gracias, revisaremos tu reporte',
                      style: texto.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'El administrador de tu barrio lo revisará pronto. '
                      'Mientras tanto, ya no verás esta publicación.',
                      style: texto.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      key: const ValueKey('report_done'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppPalette.daySecondary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Volver'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
