import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_barrio_app/core/ui_kit/app_theme.dart';
import 'package:mi_barrio_app/core/ui_kit/search_filter_bar.dart';

const _groups = [
  FilterGroup(
    id: 'modalidad',
    title: 'Modalidad',
    allLabel: 'Todas',
    options: [FilterOption('N', 'Necesito'), FilterOption('O', 'Ofrezco')],
  ),
  FilterGroup(
    id: 'tipo',
    title: 'Tipo',
    multiple: true,
    options: [FilterOption('H', 'Herramienta'), FilterOption('S', 'Soporte')],
  ),
  DistanceFilter.group,
];

Future<void> _pump(WidgetTester tester, ValueChanged<FilterSelection> onChanged,
    {FilterSelection selection = const {}}) {
  return tester.pumpWidget(MaterialApp(
    theme: AppTheme.day(),
    home: Scaffold(
      body: SearchFilterBar(
        hintText: 'Buscar',
        onSearchChanged: (_) {},
        groups: _groups,
        selection: selection,
        onFiltersChanged: onChanged,
      ),
    ),
  ));
}

bool _selected(WidgetTester tester, String key) =>
    tester.widget<FilterPill>(find.byKey(ValueKey(key))).selected;

void main() {
  testWidgets('modalidad: una sola; "Todas" por defecto; tocar de nuevo la quita',
      (tester) async {
    FilterSelection? result;
    await _pump(tester, (v) => result = v);
    await tester.tap(find.byType(FilterButton));
    await tester.pumpAndSettle();

    expect(find.text('Modalidad'), findsOneWidget);
    expect(find.text('Distancia'), findsOneWidget);
    expect(_selected(tester, 'filter_option_modalidad_all'), isTrue);

    await tester.tap(find.text('Necesito'));
    await tester.pump();
    await tester.tap(find.text('Ofrezco'));
    await tester.pump();
    expect(_selected(tester, 'filter_option_modalidad_N'), isFalse);
    expect(_selected(tester, 'filter_option_modalidad_O'), isTrue);
    expect(_selected(tester, 'filter_option_modalidad_all'), isFalse);

    await tester.tap(find.text('Ofrezco'));
    await tester.pump();
    expect(_selected(tester, 'filter_option_modalidad_all'), isTrue);

    // Tipo admite varias.
    await tester.tap(find.text('Herramienta'));
    await tester.tap(find.text('Soporte'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('filters_apply')));
    await tester.pumpAndSettle();
    expect(result!['tipo'], {'H', 'S'});
    expect(result!['modalidad'], isEmpty);
  });

  testWidgets('el botón muestra cuántos filtros hay y "Limpiar" los quita',
      (tester) async {
    FilterSelection? result;
    await _pump(tester, (v) => result = v, selection: {
      'tipo': {'H'},
      DistanceFilter.groupId: {DistanceFilter.km1},
    });
    expect(find.bySemanticsLabel('Filtros, 2 activos'), findsOneWidget);

    await tester.tap(find.byType(FilterButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('filters_clear')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('filters_apply')));
    await tester.pumpAndSettle();
    expect(activeFilterCount(result!), 0);
  });

  test('distancia: 500 m, 1 km y más lejos', () {
    expect(DistanceFilter.matches({DistanceFilter.m500}, 0.4), isTrue);
    expect(DistanceFilter.matches({DistanceFilter.m500}, 0.6), isFalse);
    expect(DistanceFilter.matches({DistanceFilter.km1}, 0.9), isTrue);
    expect(DistanceFilter.matches({DistanceFilter.farther}, 0.9), isFalse);
    expect(DistanceFilter.matches({DistanceFilter.farther}, 2), isTrue);
    expect(DistanceFilter.matches(const {}, 50), isTrue);
  });
}
