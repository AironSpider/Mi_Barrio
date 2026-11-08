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

      test('texto legible sobre el fondo del lienzo (no solo sobre tarjetas)', () {
        final bg = theme.scaffoldBackgroundColor;
        final c = theme.extension<MiBarrioColors>()!;
        expect(contrastRatio(s.onSurface, bg), greaterThanOrEqualTo(wcagAA));
        expect(contrastRatio(s.onSurfaceVariant, bg), greaterThanOrEqualTo(wcagAA));
        expect(contrastRatio(c.accentText, bg), greaterThanOrEqualTo(wcagAA));
        expect(contrastRatio(c.accentText, c.accentSoft), greaterThanOrEqualTo(wcagAA));
        expect(contrastRatio(s.onSurfaceVariant, c.hover), greaterThanOrEqualTo(wcagAA));
      });

      test('píldoras y chips de estado legibles', () {
        final c = theme.extension<MiBarrioColors>()!;
        expect(contrastRatio(c.onPill, c.pill), greaterThanOrEqualTo(wcagAA));
        expect(contrastRatio(c.syncPending, c.pendingBackground), greaterThanOrEqualTo(wcagAA));
        expect(contrastRatio(c.syncSynced, c.syncedBackground), greaterThanOrEqualTo(wcagAA));
        expect(contrastRatio(c.syncFailed, c.failedBackground), greaterThanOrEqualTo(wcagAA));
        expect(contrastRatio(c.emergencyText, c.emergencySoft), greaterThanOrEqualTo(wcagAA));
      });

      test('íconos y bordes de marca visibles (mínimo 3:1 para no-texto)', () {
        final c = theme.extension<MiBarrioColors>()!;
        for (final color in [c.brand, c.emergencyStripe, c.starFilled, c.starEmpty]) {
          expect(contrastRatio(color, Colors.white), greaterThanOrEqualTo(3.0));
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

  test('v3: los dos modos se distinguen también para un daltónico', () {
    // Un daltónico rojo-verde distingue el eje azul-amarillo. El verde anterior
    // (#1E7A2E) casi no tenía azul y se veía oliva, igual que el naranja.
    // El verde azulado lleva azul; el naranja, rojo.
    final day = AppTheme.day().colorScheme.primary;
    final emergency = AppTheme.emergency().colorScheme.primary;
    expect(day.b, greaterThan(day.r * 3));
    expect(emergency.r, greaterThan(emergency.b * 3));
  });

  test('v3: "Pendiente" ya no usa el color de "urgencia alta"', () {
    final c = AppTheme.day().extension<MiBarrioColors>()!;
    expect(c.syncPending, isNot(c.urgencyHigh));
    expect(c.urgencyCritical, isNot(AppPalette.emergencyPrimary));
  });

  test('respeta la paleta del equipo como identidad de cada modo', () {
    final day = AppTheme.day();
    final emergency = AppTheme.emergency();
    expect(day.extension<MiBarrioColors>()!.brand, AppPalette.brandGreen);
    expect(emergency.extension<MiBarrioColors>()!.brand, AppPalette.brandOrange);
    expect(day.extension<MiBarrioColors>()!.pill, const Color(0xFFE0F2FE));
    expect(day.extension<MiBarrioColors>()!.onPill, const Color(0xFF075985));
    expect(day.colorScheme.primary, const Color(0xFF0F766E));
    expect(day.scaffoldBackgroundColor, const Color(0xFFF3F4F6));
    expect(day.cardTheme.color, const Color(0xFFFFFFFF));
    expect(day.colorScheme.onSurface, const Color(0xFF1E293B));
    // Botones: mismo tono que la marca, más oscuro para texto blanco legible.
    expect(contrastRatio(day.colorScheme.primary, Colors.white), greaterThanOrEqualTo(4.5));
    expect(contrastRatio(emergency.colorScheme.primary, Colors.white), greaterThanOrEqualTo(4.5));
  });
}
