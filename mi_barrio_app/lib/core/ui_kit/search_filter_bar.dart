import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'app_theme.dart';

/// Una opción (píldora) dentro de un grupo de filtros.
class FilterOption {
  const FilterOption(this.value, this.label);

  /// Valor interno (el mismo que usan los datos, p. ej. `OFREZCO_AYUDA`).
  final String value;
  final String label;
}

/// Grupo de filtros: subtítulo + píldoras.
class FilterGroup {
  const FilterGroup({
    required this.id,
    required this.title,
    required this.options,
    this.multiple = false,
    this.allLabel,
  }) : isToggle = false;

  /// Interruptor (encendido / apagado) en lugar de píldoras.
  /// Encendido se guarda como `{FilterGroup.on}`.
  const FilterGroup.toggle({required this.id, required this.title})
    : options = const [],
      multiple = false,
      allLabel = null,
      isToggle = true;

  static const on = 'on';

  final String id;
  final String title;
  final List<FilterOption> options;

  /// true = se pueden elegir varias píldoras; false = solo una.
  final bool multiple;

  /// Si existe, se muestra primero una píldora "Todas" que queda elegida
  /// cuando el grupo no tiene ningún filtro (solo en grupos de una opción).
  final String? allLabel;

  final bool isToggle;
}

/// true si el interruptor [id] está encendido en [selection].
bool isToggleOn(FilterSelection selection, String id) =>
    selection[id]?.contains(FilterGroup.on) ?? false;

/// Filtros elegidos: id del grupo → valores elegidos. Vacío = sin filtros.
typedef FilterSelection = Map<String, Set<String>>;

/// Cuántos grupos tienen al menos un filtro activo.
int activeFilterCount(FilterSelection selection) =>
    selection.values.where((v) => v.isNotEmpty).length;

/// Buscador + botón de filtros. Es el mismo en Servicios y en Apoyo.
class SearchFilterBar extends StatelessWidget {
  const SearchFilterBar({
    super.key,
    required this.hintText,
    required this.onSearchChanged,
    required this.groups,
    required this.selection,
    required this.onFiltersChanged,
    this.searchFieldKey,
    this.filterButtonKey,
  });

  final String hintText;
  final ValueChanged<String> onSearchChanged;
  final List<FilterGroup> groups;
  final FilterSelection selection;
  final ValueChanged<FilterSelection> onFiltersChanged;
  final Key? searchFieldKey;
  final Key? filterButtonKey;

  Future<void> _openFilters(BuildContext context) async {
    final result = await showFilterDialog(
      context,
      groups: groups,
      initial: selection,
    );
    if (result != null) onFiltersChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            key: searchFieldKey,
            onChanged: onSearchChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: hintText,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        FilterButton(
          key: filterButtonKey,
          activeCount: activeFilterCount(selection),
          onPressed: () => _openFilters(context),
        ),
      ],
    );
  }
}

/// Botón de filtros sin borde: gris oscuro; con filtros activos, fondo gris
/// claro y un número (el estado no se comunica solo con color).
class FilterButton extends StatelessWidget {
  const FilterButton({
    super.key,
    required this.activeCount,
    required this.onPressed,
  });

  final int activeCount;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final active = activeCount > 0;
    return Semantics(
      button: true,
      label: !active
          ? 'Filtros'
          : activeCount == 1
          ? 'Filtros, 1 activo'
          : 'Filtros, $activeCount activos',
      // TalkBack: sin esto el doble toque no hace nada (excludeSemantics
      // quita también la acción del botón de adentro).
      onTap: onPressed,
      excludeSemantics: true,
      child: Tooltip(
        message: 'Filtros',
        child: Material(
          color: active ? AppPalette.filterActiveBackground : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onPressed,
            child: SizedBox(
              width: 52,
              height: 52,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const FaIcon(
                    FontAwesomeIcons.filter,
                    size: 20,
                    color: AppPalette.filterIcon,
                  ),
                  if (active)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 18),
                        height: 18,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(
                          '$activeCount',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onPrimary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Modal flotante centrado con los grupos de filtros.
/// Devuelve la nueva selección al tocar "Aplicar", o null si se cierra.
Future<FilterSelection?> showFilterDialog(
  BuildContext context, {
  required List<FilterGroup> groups,
  required FilterSelection initial,
}) {
  return showDialog<FilterSelection>(
    context: context,
    builder: (_) => _FilterDialog(groups: groups, initial: initial),
  );
}

class _FilterDialog extends StatefulWidget {
  const _FilterDialog({required this.groups, required this.initial});

  final List<FilterGroup> groups;
  final FilterSelection initial;

  @override
  State<_FilterDialog> createState() => _FilterDialogState();
}

class _FilterDialogState extends State<_FilterDialog> {
  late final FilterSelection _draft = {
    for (final g in widget.groups) g.id: {...?widget.initial[g.id]},
  };

  void _toggle(FilterGroup group, String value) {
    setState(() {
      final current = _draft[group.id]!;
      if (current.contains(value)) {
        // Tocar de nuevo una píldora elegida quita ese filtro.
        current.remove(value);
      } else {
        if (!group.multiple) current.clear();
        current.add(value);
      }
    });
  }

  void _clear() => setState(() {
        for (final v in _draft.values) {
          v.clear();
        }
      });

  @override
  Widget build(BuildContext context) {
    final texto = Theme.of(context).textTheme;
    final count = activeFilterCount(_draft);
    return Dialog(
      backgroundColor: AppPalette.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 8, 4),
              child: Row(
                children: [
                  Expanded(child: Text('Filtros', style: texto.titleLarge)),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < widget.groups.length; i++) ...[
                      if (i > 0)
                        SizedBox(
                          // Interruptores seguidos: más juntos.
                          height: widget.groups[i].isToggle &&
                                  widget.groups[i - 1].isToggle
                              ? 4
                              : 20,
                        ),
                      widget.groups[i].isToggle
                          ? _buildToggle(context, widget.groups[i])
                          : _buildGroup(context, widget.groups[i]),
                    ],
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: const ValueKey('filters_clear'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      onPressed: count == 0 ? null : _clear,
                      child: const Text('Limpiar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('filters_apply'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      onPressed: () => Navigator.of(context).pop(_draft),
                      child: const Text('Aplicar'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToggle(BuildContext context, FilterGroup group) {
    final selected = _draft[group.id]!;
    final on = selected.contains(FilterGroup.on);
    final primary = Theme.of(context).colorScheme.primary;
    return MergeSemantics(
      child: Row(
        children: [
          Expanded(
            child: Text(group.title, style: Theme.of(context).textTheme.bodyLarge),
          ),
          Switch(
            key: ValueKey('filter_toggle_${group.id}'),
            value: on,
            onChanged: (v) => setState(() {
              selected.clear();
              if (v) selected.add(FilterGroup.on);
            }),
            // Encendido: verde oscuro (naranja en emergencia). Apagado: blanco.
            thumbColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? Colors.white
                  : AppPalette.filterIcon,
            ),
            trackColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? primary
                  : AppPalette.card,
            ),
            trackOutlineColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? primary
                  : AppPalette.pillBorder,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroup(BuildContext context, FilterGroup group) {
    final selected = _draft[group.id]!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(group.title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (group.allLabel != null)
              FilterPill(
                key: ValueKey('filter_option_${group.id}_all'),
                label: group.allLabel!,
                selected: selected.isEmpty,
                onTap: () => setState(selected.clear),
              ),
            for (final option in group.options)
              FilterPill(
                key: ValueKey('filter_option_${group.id}_${option.value}'),
                label: option.label,
                selected: selected.contains(option.value),
                onTap: () => _toggle(group, option.value),
              ),
          ],
        ),
      ],
    );
  }
}

/// Píldora de filtro: borde gris; elegida, verde agua con ✓.
/// Usa los colores del modo actual (en emergencia, el naranja suave).
class FilterPill extends StatelessWidget {
  const FilterPill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = MiBarrioColors.of(context);
    final fg = selected ? colors.accentText : AppPalette.textPrimary;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? colors.accentSoft : AppPalette.card,
        shape: StadiumBorder(
          side: BorderSide(
            color: selected ? colors.brand : AppPalette.pillBorder,
          ),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (selected) ...[
                    Icon(Icons.check_rounded, size: 16, color: fg),
                    const SizedBox(width: 4),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      style: Theme.of(context)
                          .textTheme
                          .labelLarge
                          ?.copyWith(color: fg),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Filtro de distancia compartido (desde el punto de referencia del barrio).
class DistanceFilter {
  DistanceFilter._();

  static const groupId = 'distancia';
  static const m500 = '500m';
  static const km1 = '1km';
  static const farther = 'lejos';

  static const group = FilterGroup(
    id: groupId,
    title: 'Distancia',
    options: [
      FilterOption(m500, 'Hasta 500 m'),
      FilterOption(km1, 'Hasta 1 km'),
      FilterOption(farther, 'Más lejos'),
    ],
  );

  /// true si [km] cumple el filtro elegido (o si no hay filtro).
  static bool matches(Set<String>? selected, double km) {
    if (selected == null || selected.isEmpty) return true;
    final value = selected.first;
    return switch (value) {
      m500 => km <= 0.5,
      km1 => km <= 1,
      farther => km > 1,
      _ => true,
    };
  }
}
