import 'package:flutter/material.dart';

import '../../../../core/ui_kit/splash_screen.dart';
import '../../../profile_me/data/tutorial_progress.dart';
import 'tutorial_screen.dart';

/// Muestra el tutorial la primera vez que una cuenta entra; después, [child].
///
/// La bandera la maneja [TutorialProgress] (Dev 2): queda en el teléfono al
/// instante y se sincroniza con el perfil, así no se repite ni en otro teléfono.
class TutorialGate extends StatefulWidget {
  const TutorialGate({
    super.key,
    required this.tenantId,
    required this.userId,
    required this.child,
    this.progress,
  });

  final String tenantId;
  final String userId;
  final Widget child;
  final TutorialProgress? progress;

  @override
  State<TutorialGate> createState() => _TutorialGateState();
}

class _TutorialGateState extends State<TutorialGate> {
  late final TutorialProgress _progress = widget.progress ?? TutorialProgress();
  bool? _completed;

  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void didUpdateWidget(covariant TutorialGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) _check();
  }

  Future<void> _check() async {
    bool completed;
    try {
      completed = await _progress.isCompleted(widget.userId);
    } catch (_) {
      completed = true; // si falla la lectura, no bloqueamos la app con el tutorial
    }
    if (mounted) setState(() => _completed = completed);
  }

  Future<void> _finish() async {
    setState(() => _completed = true);
    try {
      await _progress.markCompleted(tenantId: widget.tenantId, userId: widget.userId);
    } catch (_) {
      // Si no se pudo guardar, se mostrará otra vez la próxima: no es grave.
    }
  }

  @override
  Widget build(BuildContext context) {
    return switch (_completed) {
      // Mientras se lee la bandera: la misma bienvenida que al abrir la app
      // (antes, unos segundos de pantalla gris con un indicador sin texto).
      null => const SplashScreen(),
      false => TutorialScreen(onFinished: _finish),
      true => widget.child,
    };
  }
}
