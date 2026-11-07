import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mi_barrio_app/core/ui_kit/app_theme.dart';

/// Contraste WCAG 2.1 entre dos colores.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  const wcagAA = 4.5;

  for (final entry in {
    'día a día': AppTheme.day(),
    'emergencia': AppTheme.emergency(),
  }.entries) {
    group('Tema ${entry.key}', () {
      final theme = entry.value;
      final s = theme.colorScheme;

      final pairs = <String, (Color, Color)>{
        'primary / onPrimary': (s.primary, s.onPrimary),
        'primaryContainer / onPrimaryContainer':
            (s.primaryContainer, s.onPrimaryContainer),
        'secondary / onSecondary': (s.secondary, s.onSecondary),
        'surface / onSurface': (s.surface, s.onSurface),
        'surface / onSurfaceVariant': (s.surface, s.onSurfaceVariant),
        'error / onError': (s.error, s.onError),
      };

      pairs.forEach((name, pair) {
        test('contraste AA en $name', () {
          expect(contrastRatio(pair.$1, pair.$2),
              greaterThanOrEqualTo(wcagAA));
        });
      });

      test('colores semánticos legibles sobre la superficie', () {
        final c = theme.extension<MiBarrioColors>()!;
        for (final color in [
          c.urgencyCritical,
          c.urgencyHigh,
          c.urgencyMedium,
          c.syncPending,
          c.syncSynced,
          c.syncFailed,
        ]) {
          expect(contrastRatio(color, s.surface), greaterThanOrEqualTo(wcagAA));
          expect(contrastRatio(color, Colors.white),
              greaterThanOrEqualTo(wcagAA));
        }
      });

      test('texto de cuerpo mínimo 16sp', () {
        expect(theme.textTheme.bodyMedium!.fontSize, greaterThanOrEqualTo(16));
        expect(theme.textTheme.bodyLarge!.fontSize, greaterThanOrEqualTo(16));
        expect(theme.textTheme.labelLarge!.fontSize, greaterThanOrEqualTo(16));
      });
    });
  }

  test('la extensión indica el modo correcto', () {
    expect(AppTheme.day().extension<MiBarrioColors>()!.isEmergency, isFalse);
    expect(
        AppTheme.emergency().extension<MiBarrioColors>()!.isEmergency, isTrue);
    expect(AppTheme.of(isEmergency: true).colorScheme.primary,
        AppPalette.emergencyPrimary);
  });
}
