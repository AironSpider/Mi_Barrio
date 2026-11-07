import 'package:flutter/material.dart';

/// Paletas accesibles de Mi Barrio.
///
/// Todas las combinaciones texto/fondo cumplen WCAG 2.1 AA (contraste >= 4.5:1).
/// Ver `test/ui_kit/app_theme_test.dart`, que lo verifica automáticamente.
class AppPalette {
  AppPalette._();

  // ── Modo Día a Día: verde comunidad / confianza ──
  static const Color dayPrimary = Color(0xFF0B6E4F);
  static const Color dayOnPrimary = Colors.white;
  static const Color dayPrimaryContainer = Color(0xFFCDEFE0);
  static const Color dayOnPrimaryContainer = Color(0xFF002116);
  static const Color daySecondary = Color(0xFF8A5100); // ámbar oscuro (acentos)
  static const Color daySurface = Color(0xFFF7FAF8);
  static const Color dayOnSurface = Color(0xFF1A1C1B);
  static const Color dayOnSurfaceVariant = Color(0xFF404944);

  // ── Modo Emergencia: rojo alerta, alto contraste ──
  static const Color emergencyPrimary = Color(0xFFB3261E);
  static const Color emergencyOnPrimary = Colors.white;
  static const Color emergencyPrimaryContainer = Color(0xFFFFDAD6);
  static const Color emergencyOnPrimaryContainer = Color(0xFF410002);
  static const Color emergencySecondary = Color(0xFF7A4F00);
  static const Color emergencySurface = Color(0xFFFFF8F7);
  static const Color emergencyOnSurface = Color(0xFF201A19);
  static const Color emergencyOnSurfaceVariant = Color(0xFF534341);

  // ── Semánticos compartidos ──
  static const Color urgencyCritical = Color(0xFFB3261E); // Crítica = rojo
  static const Color urgencyHigh = Color(0xFF8A5100); // Alta = ámbar oscuro
  static const Color urgencyMedium = Color(0xFF1F5FA8); // Media = azul
  static const Color syncPending = Color(0xFF8A5100); // reloj naranja
  static const Color syncSynced = Color(0xFF146C2E); // check verde
  static const Color syncFailed = Color(0xFFB3261E);
}

/// Colores semánticos accesibles desde cualquier widget:
/// `Theme.of(context).extension<MiBarrioColors>()!`
@immutable
class MiBarrioColors extends ThemeExtension<MiBarrioColors> {
  const MiBarrioColors({
    required this.isEmergency,
    required this.urgencyCritical,
    required this.urgencyHigh,
    required this.urgencyMedium,
    required this.syncPending,
    required this.syncSynced,
    required this.syncFailed,
  });

  final bool isEmergency;
  final Color urgencyCritical;
  final Color urgencyHigh;
  final Color urgencyMedium;
  final Color syncPending;
  final Color syncSynced;
  final Color syncFailed;

  static MiBarrioColors of(BuildContext context) =>
      Theme.of(context).extension<MiBarrioColors>()!;

  @override
  MiBarrioColors copyWith({
    bool? isEmergency,
    Color? urgencyCritical,
    Color? urgencyHigh,
    Color? urgencyMedium,
    Color? syncPending,
    Color? syncSynced,
    Color? syncFailed,
  }) {
    return MiBarrioColors(
      isEmergency: isEmergency ?? this.isEmergency,
      urgencyCritical: urgencyCritical ?? this.urgencyCritical,
      urgencyHigh: urgencyHigh ?? this.urgencyHigh,
      urgencyMedium: urgencyMedium ?? this.urgencyMedium,
      syncPending: syncPending ?? this.syncPending,
      syncSynced: syncSynced ?? this.syncSynced,
      syncFailed: syncFailed ?? this.syncFailed,
    );
  }

  @override
  MiBarrioColors lerp(ThemeExtension<MiBarrioColors>? other, double t) {
    if (other is! MiBarrioColors) return this;
    return MiBarrioColors(
      isEmergency: t < 0.5 ? isEmergency : other.isEmergency,
      urgencyCritical: Color.lerp(urgencyCritical, other.urgencyCritical, t)!,
      urgencyHigh: Color.lerp(urgencyHigh, other.urgencyHigh, t)!,
      urgencyMedium: Color.lerp(urgencyMedium, other.urgencyMedium, t)!,
      syncPending: Color.lerp(syncPending, other.syncPending, t)!,
      syncSynced: Color.lerp(syncSynced, other.syncSynced, t)!,
      syncFailed: Color.lerp(syncFailed, other.syncFailed, t)!,
    );
  }
}

/// Temas de la app. Uso: `AppTheme.of(isEmergency: estado)`.
///
/// Reglas de accesibilidad aplicadas (Sprint 12 ya las cumple desde el inicio):
/// - Texto de cuerpo mínimo 16sp (adultos mayores).
/// - Áreas táctiles mínimas de 48x48 dp.
/// - Contraste WCAG AA en todas las combinaciones principales.
class AppTheme {
  AppTheme._();

  /// Tamaño táctil mínimo recomendado (Material / WCAG).
  static const double minTouchTarget = 48;

  static ThemeData of({required bool isEmergency}) =>
      isEmergency ? emergency() : day();

  static ThemeData day() => _build(
        isEmergency: false,
        scheme: const ColorScheme(
          brightness: Brightness.light,
          primary: AppPalette.dayPrimary,
          onPrimary: AppPalette.dayOnPrimary,
          primaryContainer: AppPalette.dayPrimaryContainer,
          onPrimaryContainer: AppPalette.dayOnPrimaryContainer,
          secondary: AppPalette.daySecondary,
          onSecondary: Colors.white,
          error: AppPalette.urgencyCritical,
          onError: Colors.white,
          surface: AppPalette.daySurface,
          onSurface: AppPalette.dayOnSurface,
          onSurfaceVariant: AppPalette.dayOnSurfaceVariant,
          outline: Color(0xFF707973),
        ),
      );

  static ThemeData emergency() => _build(
        isEmergency: true,
        scheme: const ColorScheme(
          brightness: Brightness.light,
          primary: AppPalette.emergencyPrimary,
          onPrimary: AppPalette.emergencyOnPrimary,
          primaryContainer: AppPalette.emergencyPrimaryContainer,
          onPrimaryContainer: AppPalette.emergencyOnPrimaryContainer,
          secondary: AppPalette.emergencySecondary,
          onSecondary: Colors.white,
          error: AppPalette.urgencyCritical,
          onError: Colors.white,
          surface: AppPalette.emergencySurface,
          onSurface: AppPalette.emergencyOnSurface,
          onSurfaceVariant: AppPalette.emergencyOnSurfaceVariant,
          outline: Color(0xFF857371),
        ),
      );

  static ThemeData _build({
    required bool isEmergency,
    required ColorScheme scheme,
  }) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
    );

    final text = base.textTheme;
    final textTheme = text.copyWith(
      headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
      titleLarge: text.titleLarge?.copyWith(fontSize: 22, fontWeight: FontWeight.w700),
      titleMedium: text.titleMedium?.copyWith(fontSize: 18, fontWeight: FontWeight.w600),
      bodyLarge: text.bodyLarge?.copyWith(fontSize: 18, height: 1.4),
      bodyMedium: text.bodyMedium?.copyWith(fontSize: 16, height: 1.4),
      bodySmall: text.bodySmall?.copyWith(fontSize: 14),
      labelLarge: text.labelLarge?.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
      labelMedium: text.labelMedium?.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
    );

    return base.copyWith(
      textTheme: textTheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        centerTitle: false,
        elevation: 0,
        titleTextStyle: textTheme.titleLarge?.copyWith(color: scheme.onPrimary),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => textTheme.labelMedium?.copyWith(
            color: states.contains(WidgetState.selected)
                ? scheme.onSurface
                : scheme.onSurfaceVariant,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 28,
            color: states.contains(WidgetState.selected)
                ? scheme.onPrimaryContainer
                : scheme.onSurfaceVariant,
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        extendedTextStyle: textTheme.labelLarge?.copyWith(fontSize: 18),
        extendedSizeConstraints: const BoxConstraints(minHeight: 64, minWidth: 64),
        sizeConstraints: const BoxConstraints.tightFor(width: 64, height: 64),
        iconSize: 28,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(minTouchTarget, minTouchTarget),
          textStyle: textTheme.labelLarge,
        ),
      ),
      chipTheme: base.chipTheme.copyWith(labelStyle: textTheme.labelLarge),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      extensions: [
        MiBarrioColors(
          isEmergency: isEmergency,
          urgencyCritical: AppPalette.urgencyCritical,
          urgencyHigh: AppPalette.urgencyHigh,
          urgencyMedium: AppPalette.urgencyMedium,
          syncPending: AppPalette.syncPending,
          syncSynced: AppPalette.syncSynced,
          syncFailed: AppPalette.syncFailed,
        ),
      ],
    );
  }
}
