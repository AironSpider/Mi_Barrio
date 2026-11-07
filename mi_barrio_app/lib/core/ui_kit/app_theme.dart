import 'package:flutter/material.dart';

/// Paleta de Mi Barrio (v2, basada en psicología del color).
///
/// - **Marca** (definida por el equipo): verde para la economía local diaria,
///   naranja para emergencia, cian para etiquetas.
/// - **Acción accesible**: el mismo tono, más oscuro, para botones y texto.
///   El verde `#2AA63E` y el naranja `#F54927` no llegan al contraste 4.5:1 con
///   texto blanco, así que se usan en íconos, bordes y franjas (3:1, permitido),
///   y sus versiones oscuras en botones con texto.
///
/// `test/ui_kit/app_theme_test.dart` verifica todos los contrastes (WCAG AA).
class AppPalette {
  AppPalette._();

  // ── Marca (tal como la definió el equipo) ──
  static const Color brandGreen = Color(0xFF2AA63E); // Modo normal: íconos, Visto Bueno
  static const Color brandOrange = Color(0xFFF54927); // Emergencia: franja, bordes, íconos
  static const Color brandCyan = Color(0xFF21BCFF); // Etiquetas y píldoras

  // ── Superficies ──
  static const Color background = Color(0xFFF3F4F6); // Lienzo base
  static const Color card = Color(0xFFFFFFFF); // Tarjetas, modales
  static const Color hover = Color(0xFFF8FAFC); // Presionado / selección
  static const Color emergencyBackground = Color(0xFFFFF1EC); // Lienzo en emergencia

  // ── Texto ──
  static const Color textPrimary = Color(0xFF1E293B);
  // #64748B daba 4.32:1 sobre el fondo #F3F4F6; este tono (mismo matiz) da 4.6:1.
  static const Color textSecondary = Color(0xFF606F85);
  static const Color textOnPill = Color(0xFF0F172A); // Texto sobre #21BCFF (8.2:1)

  // ── Acción accesible: Modo normal (verde) ──
  static const Color dayPrimary = Color(0xFF1E7A2E); // Botones con texto blanco (5.4:1)
  static const Color dayOnPrimary = Colors.white;
  static const Color dayPrimaryContainer = Color(0xFFE7F6EA);
  static const Color dayOnPrimaryContainer = Color(0xFF166534);
  static const Color daySecondary = Color(0xFF0369A1);
  static const Color daySurface = card;
  static const Color dayOnSurface = textPrimary;
  static const Color dayOnSurfaceVariant = textSecondary;

  // ── Acción accesible: Modo emergencia (naranja) ──
  static const Color emergencyPrimary = Color(0xFFC2381B); // Botones con texto blanco (5.4:1)
  static const Color emergencyOnPrimary = Colors.white;
  static const Color emergencyPrimaryContainer = emergencyBackground;
  static const Color emergencyOnPrimaryContainer = Color(0xFFA82B0C);
  static const Color emergencySecondary = Color(0xFF0369A1);
  static const Color emergencySurface = card;
  static const Color emergencyOnSurface = textPrimary;
  static const Color emergencyOnSurfaceVariant = textSecondary;
  static const Color emergencyStripe = brandOrange;

  // ── Semánticos (siempre con ícono + texto, nunca solo color) ──
  static const Color urgencyCritical = Color(0xFFB3261E);
  static const Color urgencyHigh = Color(0xFF8A5300);
  static const Color urgencyMedium = Color(0xFF0369A1);
  static const Color syncPending = Color(0xFF8A5300);
  static const Color pendingBackground = Color(0xFFFFF3DC);
  static const Color syncSynced = Color(0xFF166534);
  static const Color syncedBackground = Color(0xFFE7F6EA);
  static const Color syncFailed = Color(0xFFB3261E);
  static const Color failedBackground = Color(0xFFFDECEA);
  static const Color starFilled = Color(0xFFC46A00);
  static const Color starEmpty = Color(0xFF7B8798);

  // ── Nombres anteriores (compatibilidad: no rompen código existente) ──
  static const Color accent = brandOrange;
  static const Color orangeText = emergencyOnPrimaryContainer;
  static const Color softBackground = emergencyBackground;
  static const Color pendingText = syncPending;
  static const Color tagText = textOnPill;
  static const Color tagBackground = brandCyan;
  static const Color pillBackground = hover;
}

/// Colores que dependen del modo, accesibles desde cualquier widget:
/// `MiBarrioColors.of(context)`.
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
    this.brand = AppPalette.brandGreen,
    this.accentText = AppPalette.dayOnPrimaryContainer,
    this.accentSoft = AppPalette.dayPrimaryContainer,
    this.pill = AppPalette.brandCyan,
    this.onPill = AppPalette.textOnPill,
    this.hover = AppPalette.hover,
    this.background = AppPalette.background,
    this.emergencyStripe = AppPalette.emergencyStripe,
    this.emergencySoft = AppPalette.emergencyBackground,
    this.emergencyText = AppPalette.emergencyOnPrimaryContainer,
    this.pendingBackground = AppPalette.pendingBackground,
    this.syncedBackground = AppPalette.syncedBackground,
    this.failedBackground = AppPalette.failedBackground,
    this.starFilled = AppPalette.starFilled,
    this.starEmpty = AppPalette.starEmpty,
  });

  final bool isEmergency;
  final Color urgencyCritical;
  final Color urgencyHigh;
  final Color urgencyMedium;
  final Color syncPending;
  final Color syncSynced;
  final Color syncFailed;

  /// Color de marca del modo actual (verde o naranja): íconos, bordes, franjas.
  final Color brand;

  /// Texto/ícono de acento legible sobre blanco y sobre [accentSoft].
  final Color accentText;

  /// Fondo suave del acento (selección, chips activos).
  final Color accentSoft;
  final Color pill;
  final Color onPill;
  final Color hover;
  final Color background;
  final Color emergencyStripe;
  final Color emergencySoft;
  final Color emergencyText;
  final Color pendingBackground;
  final Color syncedBackground;
  final Color failedBackground;
  final Color starFilled;
  final Color starEmpty;

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
    Color? brand,
    Color? accentText,
    Color? accentSoft,
    Color? pill,
    Color? onPill,
    Color? hover,
    Color? background,
    Color? emergencyStripe,
    Color? emergencySoft,
    Color? emergencyText,
    Color? pendingBackground,
    Color? syncedBackground,
    Color? failedBackground,
    Color? starFilled,
    Color? starEmpty,
  }) {
    return MiBarrioColors(
      isEmergency: isEmergency ?? this.isEmergency,
      urgencyCritical: urgencyCritical ?? this.urgencyCritical,
      urgencyHigh: urgencyHigh ?? this.urgencyHigh,
      urgencyMedium: urgencyMedium ?? this.urgencyMedium,
      syncPending: syncPending ?? this.syncPending,
      syncSynced: syncSynced ?? this.syncSynced,
      syncFailed: syncFailed ?? this.syncFailed,
      brand: brand ?? this.brand,
      accentText: accentText ?? this.accentText,
      accentSoft: accentSoft ?? this.accentSoft,
      pill: pill ?? this.pill,
      onPill: onPill ?? this.onPill,
      hover: hover ?? this.hover,
      background: background ?? this.background,
      emergencyStripe: emergencyStripe ?? this.emergencyStripe,
      emergencySoft: emergencySoft ?? this.emergencySoft,
      emergencyText: emergencyText ?? this.emergencyText,
      pendingBackground: pendingBackground ?? this.pendingBackground,
      syncedBackground: syncedBackground ?? this.syncedBackground,
      failedBackground: failedBackground ?? this.failedBackground,
      starFilled: starFilled ?? this.starFilled,
      starEmpty: starEmpty ?? this.starEmpty,
    );
  }

  @override
  MiBarrioColors lerp(ThemeExtension<MiBarrioColors>? other, double t) {
    if (other is! MiBarrioColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return MiBarrioColors(
      isEmergency: t < 0.5 ? isEmergency : other.isEmergency,
      urgencyCritical: l(urgencyCritical, other.urgencyCritical),
      urgencyHigh: l(urgencyHigh, other.urgencyHigh),
      urgencyMedium: l(urgencyMedium, other.urgencyMedium),
      syncPending: l(syncPending, other.syncPending),
      syncSynced: l(syncSynced, other.syncSynced),
      syncFailed: l(syncFailed, other.syncFailed),
      brand: l(brand, other.brand),
      accentText: l(accentText, other.accentText),
      accentSoft: l(accentSoft, other.accentSoft),
      pill: l(pill, other.pill),
      onPill: l(onPill, other.onPill),
      hover: l(hover, other.hover),
      background: l(background, other.background),
      emergencyStripe: l(emergencyStripe, other.emergencyStripe),
      emergencySoft: l(emergencySoft, other.emergencySoft),
      emergencyText: l(emergencyText, other.emergencyText),
      pendingBackground: l(pendingBackground, other.pendingBackground),
      syncedBackground: l(syncedBackground, other.syncedBackground),
      failedBackground: l(failedBackground, other.failedBackground),
      starFilled: l(starFilled, other.starFilled),
      starEmpty: l(starEmpty, other.starEmpty),
    );
  }
}

class AppTheme {
  AppTheme._();

  static const double minTouchTarget = 48;

  static ThemeData of({required bool isEmergency}) =>
      isEmergency ? emergency() : day();

  static ThemeData day() => _build(
    isEmergency: false,
    background: AppPalette.background,
    scheme: const ColorScheme(
      brightness: Brightness.light,
      primary: AppPalette.dayPrimary,
      onPrimary: AppPalette.dayOnPrimary,
      primaryContainer: AppPalette.dayPrimaryContainer,
      onPrimaryContainer: AppPalette.dayOnPrimaryContainer,
      secondary: AppPalette.daySecondary,
      onSecondary: Colors.white,
      tertiary: AppPalette.brandCyan,
      onTertiary: AppPalette.textOnPill,
      error: AppPalette.urgencyCritical,
      onError: Colors.white,
      surface: AppPalette.daySurface,
      onSurface: AppPalette.dayOnSurface,
      onSurfaceVariant: AppPalette.dayOnSurfaceVariant,
      outline: Color(0xFF8A96A8),
      outlineVariant: Color(0xFFE2E8F0),
    ),
    extension: const MiBarrioColors(
      isEmergency: false,
      urgencyCritical: AppPalette.urgencyCritical,
      urgencyHigh: AppPalette.urgencyHigh,
      urgencyMedium: AppPalette.urgencyMedium,
      syncPending: AppPalette.syncPending,
      syncSynced: AppPalette.syncSynced,
      syncFailed: AppPalette.syncFailed,
      brand: AppPalette.brandGreen,
      accentText: AppPalette.dayOnPrimaryContainer,
      accentSoft: AppPalette.dayPrimaryContainer,
      background: AppPalette.background,
    ),
  );

  static ThemeData emergency() => _build(
    isEmergency: true,
    background: AppPalette.emergencyBackground,
    scheme: const ColorScheme(
      brightness: Brightness.light,
      primary: AppPalette.emergencyPrimary,
      onPrimary: AppPalette.emergencyOnPrimary,
      primaryContainer: AppPalette.emergencyPrimaryContainer,
      onPrimaryContainer: AppPalette.emergencyOnPrimaryContainer,
      secondary: AppPalette.emergencySecondary,
      onSecondary: Colors.white,
      tertiary: AppPalette.brandCyan,
      onTertiary: AppPalette.textOnPill,
      error: AppPalette.urgencyCritical,
      onError: Colors.white,
      surface: AppPalette.emergencySurface,
      onSurface: AppPalette.emergencyOnSurface,
      onSurfaceVariant: AppPalette.emergencyOnSurfaceVariant,
      outline: Color(0xFF8A96A8),
      outlineVariant: Color(0xFFF5D0C5),
    ),
    extension: const MiBarrioColors(
      isEmergency: true,
      urgencyCritical: AppPalette.urgencyCritical,
      urgencyHigh: AppPalette.urgencyHigh,
      urgencyMedium: AppPalette.urgencyMedium,
      syncPending: AppPalette.syncPending,
      syncSynced: AppPalette.syncSynced,
      syncFailed: AppPalette.syncFailed,
      brand: AppPalette.brandOrange,
      accentText: AppPalette.emergencyOnPrimaryContainer,
      accentSoft: AppPalette.emergencyPrimaryContainer,
      background: AppPalette.emergencyBackground,
    ),
  );

  static ThemeData _build({
    required bool isEmergency,
    required Color background,
    required ColorScheme scheme,
    required MiBarrioColors extension,
  }) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      visualDensity: VisualDensity.standard,
    );

    final text = base.textTheme.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );
    final textTheme = text.copyWith(
      headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
      titleLarge: text.titleLarge?.copyWith(
        fontSize: 22,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: text.titleMedium?.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: text.bodyLarge?.copyWith(fontSize: 18, height: 1.4),
      bodyMedium: text.bodyMedium?.copyWith(fontSize: 16, height: 1.4),
      bodySmall: text.bodySmall?.copyWith(fontSize: 14),
      labelLarge: text.labelLarge?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      labelMedium: text.labelMedium?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
    );

    return base.copyWith(
      textTheme: textTheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      hoverColor: AppPalette.hover,
      highlightColor: AppPalette.hover,
      cardTheme: CardThemeData(
        color: AppPalette.card,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        centerTitle: false,
        elevation: 0,
        titleTextStyle: textTheme.titleLarge?.copyWith(color: scheme.onPrimary),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: AppPalette.card,
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
        extendedSizeConstraints: const BoxConstraints(
          minHeight: 64,
          minWidth: 64,
        ),
        sizeConstraints: const BoxConstraints.tightFor(width: 64, height: 64),
        iconSize: 28,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(minTouchTarget, minTouchTarget),
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(minTouchTarget, minTouchTarget),
          textStyle: textTheme.labelLarge,
        ),
      ),
      // Selección en controles segmentados con el color del modo (verde / naranja).
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? scheme.primary
                : AppPalette.card,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? scheme.onPrimary
                : scheme.onSurface,
          ),
          iconColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? scheme.onPrimary
                : scheme.onSurface,
          ),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        labelStyle: textTheme.labelLarge,
        selectedColor: AppPalette.brandCyan,
        secondaryLabelStyle: textTheme.labelLarge?.copyWith(
          color: AppPalette.textOnPill,
        ),
        checkmarkColor: AppPalette.textOnPill,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
      extensions: [extension],
    );
  }
}
