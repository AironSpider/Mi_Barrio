import 'package:flutter/material.dart';

import 'app_select_field.dart';
import 'emergency_toggle.dart';
import 'filter_pill.dart';
import 'filters_bottom_sheet.dart';
import 'star_rating_display.dart';
import 'star_rating_input.dart';
import 'sync_status_chip.dart';

class UiKitPreviewScreen extends StatefulWidget {
  const UiKitPreviewScreen({super.key});

  @override
  State<UiKitPreviewScreen> createState() => _UiKitPreviewScreenState();
}

class _UiKitPreviewScreenState extends State<UiKitPreviewScreen> {
  bool _emergencia = false;
  int _estrellas = 0;
  String? _tipo = 'PERSONA_NATURAL';
  final Set<String> _pildoras = {};
  FiltersValue _filtros = const FiltersValue();

  static const List<AppSelectOption<String>> _tipos = [
    AppSelectOption(
      value: 'PERSONA_NATURAL',
      label: 'Persona natural',
      icon: Icons.person_rounded,
    ),
    AppSelectOption(
      value: 'EMPRENDEDOR',
      label: 'Emprendedor',
      icon: Icons.lightbulb_rounded,
    ),
    AppSelectOption(
      value: 'BODEGA',
      label: 'Bodega',
      icon: Icons.storefront_rounded,
    ),
    AppSelectOption(
      value: 'MINI_EMPRESA',
      label: 'Mini empresa',
      icon: Icons.store_rounded,
    ),
    AppSelectOption(
      value: 'EMPRESA',
      label: 'Empresa',
      icon: Icons.business_rounded,
    ),
  ];

  static const List<AppSelectOption<String>> _zonas = [
    AppSelectOption(value: 'CENTRO', label: 'Comunidad centro'),
    AppSelectOption(value: 'NORTE', label: 'Zona norte'),
    AppSelectOption(value: 'SUR', label: 'Zona sur'),
  ];

  static const List<AppSelectOption<String>> _rubros = [
    AppSelectOption(
      value: 'GASFITERIA',
      label: 'Gasfitería',
      icon: Icons.plumbing_rounded,
    ),
    AppSelectOption(
      value: 'ELECTRICIDAD',
      label: 'Electricidad',
      icon: Icons.electrical_services_rounded,
    ),
    AppSelectOption(
      value: 'CARPINTERIA',
      label: 'Carpintería',
      icon: Icons.carpenter_rounded,
    ),
    AppSelectOption(
      value: 'CLASES',
      label: 'Clases',
      icon: Icons.school_rounded,
    ),
    AppSelectOption(
      value: 'PASEADOR_MASCOTAS',
      label: 'Mascotas',
      icon: Icons.pets_rounded,
    ),
  ];

  static const Map<String, String> _opcionesPildoras = {
    'CENTRO': 'Comunidad centro',
    'GASFITERIA': 'Gasfitería',
    'ELECTRICIDAD': 'Electricidad',
    'CARPINTERIA': 'Carpintería',
  };

  Future<void> _abrirFiltros() async {
    final resultado = await showFiltersBottomSheet(
      context,
      initial: _filtros,
      zones: _zonas,
      categories: _rubros,
    );
    if (resultado != null && mounted) {
      setState(() => _filtros = resultado);
    }
  }

  void _alternarPildora(String clave) {
    setState(() {
      if (_pildoras.contains(clave)) {
        _pildoras.remove(clave);
      } else {
        _pildoras.add(clave);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(top: 16, bottom: 96),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search_rounded),
                    hintText: 'Buscar oficios o vecinos',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FiltersIconButton(
                activeCount: _filtros.activeCount,
                onPressed: _abrirFiltros,
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        FilterPillBar(
          options: _opcionesPildoras,
          selected: _pildoras,
          onToggle: _alternarPildora,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: EmergencyToggle(
            value: _emergencia,
            onChanged: (valor) => setState(() => _emergencia = valor),
          ),
        ),
        const _Seccion(
          titulo: 'Estado de sincronización',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SyncStatusChip(status: SyncChipStatus.pending),
              SyncStatusChip(status: SyncChipStatus.synced),
              SyncStatusChip(status: SyncChipStatus.failed),
            ],
          ),
        ),
        const _Seccion(
          titulo: 'Calificación promedio',
          child: StarRatingDisplay(rating: 4.5, count: 12),
        ),
        _Seccion(
          titulo: 'Califica este servicio',
          child: Center(
            child: StarRatingInput(
              value: _estrellas,
              onChanged: (valor) => setState(() => _estrellas = valor),
            ),
          ),
        ),
        _Seccion(
          titulo: 'Tu perfil',
          child: AppSelectField<String>(
            label: 'Tipo de publicador',
            options: _tipos,
            value: _tipo,
            onChanged: (valor) => setState(() => _tipo = valor),
          ),
        ),
      ],
    );
  }
}

class _Seccion extends StatelessWidget {
  const _Seccion({required this.titulo, required this.child});

  final String titulo;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
