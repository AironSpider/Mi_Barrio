import 'dart:async';

import 'package:flutter/material.dart';

import 'app_theme.dart';

/// Pantalla al abrir la app mientras se lee la sesión guardada.
///
/// En vez de un indicador solo, muestra el logo y dice qué pasa. Si tarda
/// (servidor despertando o señal débil), avisa que entrará igual con lo
/// guardado en el teléfono, para que nadie piense que la app se colgó.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  static const slowKey = ValueKey('splash_slow');

  /// Después de este tiempo se muestra el aviso de conexión lenta.
  static const slowAfter = Duration(seconds: 3);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _timer;
  bool _slow = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(SplashScreen.slowAfter, () {
      if (mounted) setState(() => _slow = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: AppPalette.card,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/images/logo_mi_barrio.png',
                    width: 132,
                    height: 132,
                    excludeFromSemantics: true,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Mi Barrio',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: AppPalette.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 28),
                  const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                  const SizedBox(height: 16),
                  Semantics(
                    liveRegion: true,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: Text(
                        _slow
                            ? 'La conexión está lenta. En unos segundos entras '
                                  'con lo guardado en tu teléfono.'
                            : 'Abriendo tu barrio…',
                        key: _slow ? SplashScreen.slowKey : null,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: AppPalette.textPrimary,
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
