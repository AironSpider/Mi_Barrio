import 'package:flutter/material.dart';

import 'app_select_field.dart';
import 'app_theme.dart';

class FiltersValue {
  const FiltersValue({this.zone, this.category});

  final String? zone;
  final String? category;

  bool get isEmpty => zone == null && category == null;

  int get activeCount => (zone == null ? 0 : 1) + (category == null ? 0 : 1);
}

Future<FiltersValue?> showFiltersBottomSheet(
  BuildContext context, {
  required FiltersValue initial,
  required List<AppSelectOption<String>> zones,
  required List<AppSelectOption<String>> categories,
}) {
  return showModalBottomSheet<FiltersValue>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) =>
        _FiltersSheet(initial: initial, zones: zones, categories: categories),
  );
}

class FiltersIconButton extends StatelessWidget {
  const FiltersIconButton({
    super.key,
    required this.activeCount,
    required this.onPressed,
  });

  final int activeCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: activeCount == 0 ? 'Filtros' : 'Filtros, $activeCount activos',
      excludeSemantics: true,
      child: Badge(
        isLabelVisible: activeCount > 0,
        label: Text('$activeCount'),
        child: IconButton.outlined(
          onPressed: onPressed,
          constraints: const BoxConstraints(
            minWidth: AppTheme.minTouchTarget,
            minHeight: AppTheme.minTouchTarget,
          ),
          icon: const Icon(Icons.tune_rounded),
        ),
      ),
    );
  }
}

class _FiltersSheet extends StatefulWidget {
  const _FiltersSheet({
    required this.initial,
    required this.zones,
    required this.categories,
  });

  final FiltersValue initial;
  final List<AppSelectOption<String>> zones;
  final List<AppSelectOption<String>> categories;

  @override
  State<_FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends State<_FiltersSheet> {
  late String? _zona = widget.initial.zone;
  late String? _rubro = widget.initial.category;

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Filtros', style: texto.titleLarge),
            const SizedBox(height: 20),
            AppSelectField<String>(
              label: 'Zona',
              hint: 'Todas las zonas',
              options: widget.zones,
              value: _zona,
              allowClear: true,
              onChanged: (valor) => setState(() => _zona = valor),
            ),
            const SizedBox(height: 16),
            AppSelectField<String>(
              label: 'Rubro',
              hint: 'Todos los rubros',
              options: widget.categories,
              value: _rubro,
              allowClear: true,
              onChanged: (valor) => setState(() => _rubro = valor),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                    ),
                    onPressed: () =>
                        Navigator.of(context).pop(const FiltersValue()),
                    child: const Text('Limpiar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                    ),
                    onPressed: () =>
                        Navigator.of(context)
                            .pop(FiltersValue(zone: _zona, category: _rubro)),
                    child: const Text('Aplicar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
