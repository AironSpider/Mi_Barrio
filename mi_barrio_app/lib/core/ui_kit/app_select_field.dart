import 'package:flutter/material.dart';

import 'app_theme.dart';

class AppSelectOption<T> {
  const AppSelectOption({required this.value, required this.label, this.icon});

  final T value;
  final String label;
  final IconData? icon;
}

class _SelectResult<T> {
  const _SelectResult(this.value);

  final T? value;
}

class AppSelectField<T> extends StatelessWidget {
  const AppSelectField({
    super.key,
    required this.label,
    required this.options,
    required this.value,
    required this.onChanged,
    this.hint = 'Selecciona una opción',
    this.allowClear = false,
  });

  final String label;
  final List<AppSelectOption<T>> options;
  final T? value;
  final ValueChanged<T?>? onChanged;
  final String hint;
  final bool allowClear;

  AppSelectOption<T>? get _seleccionada {
    for (final opcion in options) {
      if (opcion.value == value) return opcion;
    }
    return null;
  }

  Future<void> _abrir(BuildContext context) async {
    final resultado = await showModalBottomSheet<_SelectResult<T>>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => _SelectSheet<T>(
        label: label,
        options: options,
        value: value,
        allowClear: allowClear,
      ),
    );
    if (resultado != null) onChanged?.call(resultado.value);
  }

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final texto = Theme.of(context).textTheme;
    final seleccionada = _seleccionada;
    final habilitado = onChanged != null;

    return Semantics(
      button: true,
      label: '$label: ${seleccionada?.label ?? hint}',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: habilitado ? () => _abrir(context) : null,
        child: InputDecorator(
          isEmpty: false,
          decoration: InputDecoration(
            labelText: label,
            enabled: habilitado,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            prefixIcon: seleccionada?.icon == null
                ? null
                : Icon(seleccionada!.icon, color: AppPalette.orangeText),
            suffixIcon: const Icon(Icons.expand_more_rounded),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
          ),
          child: Text(
            seleccionada?.label ?? hint,
            style: texto.bodyLarge?.copyWith(
              color: seleccionada == null
                  ? esquema.onSurfaceVariant
                  : esquema.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectSheet<T> extends StatelessWidget {
  const _SelectSheet({
    required this.label,
    required this.options,
    required this.value,
    required this.allowClear,
  });

  final String label;
  final List<AppSelectOption<T>> options;
  final T? value;
  final bool allowClear;

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Text(label, style: texto.titleLarge),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final opcion in options)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 4,
                  ),
                  leading: opcion.icon == null ? null : Icon(opcion.icon),
                  title: Text(opcion.label, style: texto.bodyLarge),
                  trailing: opcion.value == value
                      ? const Icon(
                          Icons.check_rounded,
                          color: AppPalette.orangeText,
                        )
                      : null,
                  selected: opcion.value == value,
                  selectedColor: AppPalette.orangeText,
                  selectedTileColor: AppPalette.softBackground,
                  onTap: () =>
                      Navigator.of(context).pop(_SelectResult<T>(opcion.value)),
                ),
            ],
          ),
        ),
        if (allowClear && value != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextButton.icon(
              onPressed: () =>
                  Navigator.of(context).pop(_SelectResult<T>(null)),
              icon: const Icon(Icons.close_rounded),
              label: const Text('Quitar selección'),
            ),
          ),
        const SizedBox(height: 16),
      ],
    );
  }
}
