import 'package:flutter/material.dart';

import '../../features/solidarity_network/data/models/solidarity_post_model.dart';

class QuickPublishData {
  const QuickPublishData({
    required this.modality,
    required this.flowType,
    required this.title,
    required this.isEmergencyContext,
  });

  final String modality;
  final String flowType;
  final String title;
  final bool isEmergencyContext;
}

typedef QuickPublishCallback = Future<void> Function(QuickPublishData data);

Future<void> showQuickPublishModal(
  BuildContext context, {
  required bool isEmergencyMode,
  required QuickPublishCallback onPublish,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => _QuickPublishSheet(
      isEmergencyMode: isEmergencyMode,
      onPublish: onPublish,
    ),
  );
}

class _Categoria {
  const _Categoria(this.modality, this.label, this.icon);

  final String modality;
  final String label;
  final IconData icon;
}

class _QuickPublishSheet extends StatefulWidget {
  const _QuickPublishSheet({
    required this.isEmergencyMode,
    required this.onPublish,
  });

  final bool isEmergencyMode;
  final QuickPublishCallback onPublish;

  @override
  State<_QuickPublishSheet> createState() => _QuickPublishSheetState();
}

class _QuickPublishSheetState extends State<_QuickPublishSheet> {
  final TextEditingController _titulo = TextEditingController();
  String? _modalidad;
  String _flujo = SolidarityFlowType.solicitoAyuda;
  bool _guardando = false;
  String? _error;

  List<_Categoria> get _categorias => [
    const _Categoria(
      SolidarityModality.prestamoHerramienta,
      'Herramienta',
      Icons.hardware_rounded,
    ),
    const _Categoria(
      SolidarityModality.intercambioHabilidad,
      'Habilidad',
      Icons.school_rounded,
    ),
    const _Categoria(
      SolidarityModality.donacionMaterial,
      'Material',
      Icons.inventory_2_rounded,
    ),
    const _Categoria(
      SolidarityModality.ayudaTemporal,
      'Soporte',
      Icons.volunteer_activism_rounded,
    ),
    if (widget.isEmergencyMode)
      const _Categoria(
        SolidarityModality.recursoCritico,
        'Recurso crítico',
        Icons.emergency_rounded,
      ),
  ];

  bool get _puedePublicar =>
      !_guardando && _modalidad != null && _titulo.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _titulo.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _titulo.dispose();
    super.dispose();
  }

  Future<void> _publicar() async {
    if (!_puedePublicar) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await widget.onPublish(
        QuickPublishData(
          modality: _modalidad!,
          flowType: _flujo,
          title: _titulo.text.trim(),
          isEmergencyContext: widget.isEmergencyMode,
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _guardando = false;
        _error = 'No se pudo guardar. Intenta de nuevo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final texto = Theme.of(context).textTheme;
    final teclado = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: teclado),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.isEmergencyMode ? 'Pedir ayuda' : 'Publicar en tu barrio',
              style: texto.titleLarge,
            ),
            const SizedBox(height: 16),
            SegmentedButton<String>(
              style: SegmentedButton.styleFrom(minimumSize: const Size(48, 52)),
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: SolidarityFlowType.solicitoAyuda,
                  label: Text('Necesito'),
                  icon: Icon(Icons.back_hand_rounded),
                ),
                ButtonSegment(
                  value: SolidarityFlowType.ofrezcoAyuda,
                  label: Text('Ofrezco'),
                  icon: Icon(Icons.favorite_rounded),
                ),
              ],
              selected: {_flujo},
              onSelectionChanged: (valor) =>
                  setState(() => _flujo = valor.first),
            ),
            const SizedBox(height: 20),
            Text('¿Qué tipo es?', style: texto.titleMedium),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 2.4,
              children: [
                for (final categoria in _categorias)
                  _CategoriaTile(
                    categoria: categoria,
                    seleccionada: _modalidad == categoria.modality,
                    onTap: () =>
                        setState(() => _modalidad = categoria.modality),
                  ),
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: _modalidad == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: 20),
                      child: TextField(
                        controller: _titulo,
                        autofocus: true,
                        maxLength: 80,
                        textCapitalization: TextCapitalization.sentences,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _publicar(),
                        style: texto.bodyLarge,
                        decoration: InputDecoration(
                          labelText: 'Cuéntalo en una línea',
                          hintText: 'Ej: Préstamo de escalera',
                          counterText: '',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: texto.bodyMedium?.copyWith(color: esquema.error),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                ),
                onPressed: _puedePublicar ? _publicar : null,
                icon: _guardando
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : const Icon(Icons.check_rounded),
                label: const Text('Publicar ahora'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoriaTile extends StatelessWidget {
  const _CategoriaTile({
    required this.categoria,
    required this.seleccionada,
    required this.onTap,
  });

  final _Categoria categoria;
  final bool seleccionada;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final texto = Theme.of(context).textTheme;
    final fondo = seleccionada ? esquema.primary : esquema.primaryContainer;
    final contenido = seleccionada
        ? esquema.onPrimary
        : esquema.onPrimaryContainer;

    return Semantics(
      button: true,
      selected: seleccionada,
      label: categoria.label,
      excludeSemantics: true,
      child: Material(
        color: fondo,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(categoria.icon, size: 28, color: contenido),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    categoria.label,
                    style: texto.labelLarge?.copyWith(color: contenido),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
