import 'package:flutter/material.dart';

import '../../data/onboarding_local_storage.dart';
import 'tutorial_screen.dart';

/// Muestra el tutorial la primera vez que una cuenta entra; después, [child].
class TutorialGate extends StatefulWidget {
  const TutorialGate({super.key, required this.userId, required this.child, this.storage});

  final String userId;
  final Widget child;
  final OnboardingLocalStorage? storage;

  @override
  State<TutorialGate> createState() => _TutorialGateState();
}

class _TutorialGateState extends State<TutorialGate> {
  late final OnboardingLocalStorage _storage = widget.storage ?? OnboardingLocalStorage();
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
      completed = await _storage.isCompleted(widget.userId);
    } catch (_) {
      completed = true; // si falla la lectura, no bloqueamos la app con el tutorial
    }
    if (mounted) setState(() => _completed = completed);
  }

  Future<void> _finish() async {
    setState(() => _completed = true);
    try {
      await _storage.markCompleted(widget.userId);
    } catch (_) {
      // Si no se pudo guardar, se mostrará otra vez la próxima: no es grave.
    }
  }

  @override
  Widget build(BuildContext context) {
    return switch (_completed) {
      null => const Scaffold(body: Center(child: CircularProgressIndicator())),
      false => TutorialScreen(onFinished: _finish),
      true => widget.child,
    };
  }
}
