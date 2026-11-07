import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/ui_kit/app_theme.dart';

class VistoBuenoBadge extends StatefulWidget {
  const VistoBuenoBadge({
    super.key,
    required this.count,
    required this.isEndorsed,
    this.onPressed,
  });

  final int count;
  final bool isEndorsed;
  final VoidCallback? onPressed;

  @override
  State<VistoBuenoBadge> createState() => _VistoBuenoBadgeState();
}

class _VistoBuenoBadgeState extends State<VistoBuenoBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.0,
          end: 1.28,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.28,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.elasticOut)),
        weight: 60,
      ),
    ]).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _alTocar() {
    HapticFeedback.lightImpact();
    _controller.forward(from: 0);
    widget.onPressed?.call();
  }

  @override
  Widget build(BuildContext context) {
    final esquema = Theme.of(context).colorScheme;
    final colores = MiBarrioColors.of(context);
    final texto = Theme.of(context).textTheme;

    final fondo = widget.isEndorsed ? esquema.primary : Colors.transparent;
    final contenido = widget.isEndorsed ? esquema.onPrimary : esquema.primary;
    final borde = esquema.primary;

    final etiqueta = widget.isEndorsed
        ? 'Visto bueno dado. ${widget.count} recomendaciones'
        : 'Dar visto bueno. ${widget.count} recomendaciones';

    return Semantics(
      button: true,
      label: etiqueta,
      excludeSemantics: true,
      child: ScaleTransition(
        scale: _scale,
        child: Material(
          color: fondo,
          shape: StadiumBorder(side: BorderSide(color: borde, width: 2)),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: widget.onPressed == null ? null : _alTocar,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: AppTheme.minTouchTarget,
                minWidth: AppTheme.minTouchTarget,
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      transitionBuilder: (hijo, animacion) =>
                          ScaleTransition(scale: animacion, child: hijo),
                      child: Icon(
                        widget.isEndorsed
                            ? Icons.verified_user
                            : Icons.verified_user_outlined,
                        key: ValueKey(widget.isEndorsed),
                        size: 26,
                        color: contenido,
                      ),
                    ),
                    const SizedBox(width: 8),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      transitionBuilder: (hijo, animacion) => FadeTransition(
                        opacity: animacion,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.5),
                            end: Offset.zero,
                          ).animate(animacion),
                          child: hijo,
                        ),
                      ),
                      child: Text(
                        '${widget.count}',
                        key: ValueKey(widget.count),
                        style: texto.titleMedium?.copyWith(
                          color: contenido,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      widget.isEndorsed ? 'Recomendado' : 'Visto bueno',
                      style: texto.labelLarge?.copyWith(
                        color: widget.isEndorsed
                            ? contenido
                            : colores.isEmergency
                            ? esquema.onSurface
                            : esquema.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
