import 'package:flutter/material.dart';

import '../widgets/tutorial_step_card.dart';

/// Tutorial de bienvenida: 3 pasos, se muestra solo la primera vez.
///
/// "Saltar" y "Empezar" llaman a [onFinished]; quien lo muestra guarda que ya se vio.
class TutorialScreen extends StatefulWidget {
  const TutorialScreen({super.key, required this.onFinished});

  final VoidCallback onFinished;

  static const nextKey = ValueKey('tutorial_next');
  static const skipKey = ValueKey('tutorial_skip');

  static const steps = [
    (
      icon: Icons.handyman_rounded,
      title: 'Oficios de confianza',
      description: 'Encuentra gasfiteros, electricistas y más de tu barrio, '
          'con las estrellas que les dieron tus vecinos.',
    ),
    (
      icon: Icons.volunteer_activism_rounded,
      title: 'Favores sin dinero',
      description: 'Pide o presta herramientas, ayuda y movilidad. '
          'Publicas en 3 toques, incluso sin internet.',
    ),
    (
      icon: Icons.warning_amber_rounded,
      title: 'Pedir ayuda en emergencia',
      description: 'Si hay una emergencia, toca "Pedir ayuda". Tu pedido se guarda '
          'en el teléfono y llega a tus vecinos apenas vuelva la señal.',
    ),
  ];

  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen> {
  final _pages = PageController();
  int _index = 0;

  bool get _isLast => _index == TutorialScreen.steps.length - 1;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _next() {
    if (_isLast) {
      widget.onFinished();
      return;
    }
    _pages.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = TutorialScreen.steps.length;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: TextButton(
                  key: TutorialScreen.skipKey,
                  onPressed: widget.onFinished,
                  child: const Text('Saltar'),
                ),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: (i) => setState(() => _index = i),
                children: [
                  for (final step in TutorialScreen.steps)
                    TutorialStepCard(icon: step.icon, title: step.title, description: step.description),
                ],
              ),
            ),
            // Indicador con texto (no solo puntos) para lectores de pantalla.
            Semantics(
              liveRegion: true,
              child: Text('Paso ${_index + 1} de $total', style: theme.textTheme.bodyMedium),
            ),
            const SizedBox(height: 8),
            ExcludeSemantics(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < total; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: i == _index ? 24 : 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: i == _index ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: TutorialScreen.nextKey,
                  onPressed: _next,
                  child: Text(_isLast ? 'Empezar' : 'Siguiente'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
