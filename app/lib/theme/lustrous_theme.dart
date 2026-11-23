import 'package:flutter/material.dart';

/// Paired background + foreground colors for a Lustrous categorical speaker badge.
@immutable
class LustrousCategoryColor {
  final Color container;
  final Color onContainer;

  const LustrousCategoryColor({
    required this.container,
    required this.onContainer,
  });

  static LustrousCategoryColor lerp(
    LustrousCategoryColor a,
    LustrousCategoryColor b,
    double t,
  ) {
    return LustrousCategoryColor(
      container: Color.lerp(a.container, b.container, t)!,
      onContainer: Color.lerp(a.onContainer, b.onContainer, t)!,
    );
  }
}

/// Semantic & categorical color tokens aligned with `@ghchinoy/lustrous-lit`
/// (Mineral Slate light / Obsidian Slate dark + Lustrous Sapphire + Mineral Teal).
@immutable
class LustrousColors extends ThemeExtension<LustrousColors> {
  final Color positive;
  final Color positiveContainer;
  final Color onPositiveContainer;
  final Color warning;
  final Color warningContainer;
  final Color onWarningContainer;
  final Color danger;
  final Color dangerContainer;
  final Color onDangerContainer;
  final List<LustrousCategoryColor> speakerPalette;

  const LustrousColors({
    required this.positive,
    required this.positiveContainer,
    required this.onPositiveContainer,
    required this.warning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.danger,
    required this.dangerContainer,
    required this.onDangerContainer,
    required this.speakerPalette,
  });

  /// Light mode (Mineral Slate) tokens from `@ghchinoy/lustrous-lit`.
  static const LustrousColors light = LustrousColors(
    positive: Color(0xFF047857),
    positiveContainer: Color(0xFFD1FAE5),
    onPositiveContainer: Color(0xFF065F46),
    warning: Color(0xFFB45309),
    warningContainer: Color(0xFFFEF3C7),
    onWarningContainer: Color(0xFF92400E),
    danger: Color(0xFFB91C1C),
    dangerContainer: Color(0xFFFEE2E2),
    onDangerContainer: Color(0xFF991B1B),
    speakerPalette: [
      LustrousCategoryColor(container: Color(0xFFDBEAFE), onContainer: Color(0xFF1E40AF)), // cobalt
      LustrousCategoryColor(container: Color(0xFFD1FAE5), onContainer: Color(0xFF065F46)), // emerald
      LustrousCategoryColor(container: Color(0xFFFEF3C7), onContainer: Color(0xFF92400E)), // amber
      LustrousCategoryColor(container: Color(0xFFFFE4E6), onContainer: Color(0xFF9F1239)), // rose
      LustrousCategoryColor(container: Color(0xFFEDE9FE), onContainer: Color(0xFF5B21B6)), // violet
      LustrousCategoryColor(container: Color(0xFFCCFBF1), onContainer: Color(0xFF115E59)), // teal
    ],
  );

  /// Dark mode (Obsidian Slate) tokens from `@ghchinoy/lustrous-lit`.
  static const LustrousColors dark = LustrousColors(
    positive: Color(0xFF34D399),
    positiveContainer: Color(0xFF064E3B),
    onPositiveContainer: Color(0xFFD1FAE5),
    warning: Color(0xFFFBBF24),
    warningContainer: Color(0xFF78350F),
    onWarningContainer: Color(0xFFFEF3C7),
    danger: Color(0xFFF87171),
    dangerContainer: Color(0xFF7F1D1D),
    onDangerContainer: Color(0xFFFEE2E2),
    speakerPalette: [
      LustrousCategoryColor(container: Color(0xFF172554), onContainer: Color(0xFFBFDBFE)), // cobalt
      LustrousCategoryColor(container: Color(0xFF064E3B), onContainer: Color(0xFFA7F3D0)), // emerald
      LustrousCategoryColor(container: Color(0xFF451A03), onContainer: Color(0xFFFDE68A)), // amber
      LustrousCategoryColor(container: Color(0xFF4C0519), onContainer: Color(0xFFFECDD3)), // rose
      LustrousCategoryColor(container: Color(0xFF2E1065), onContainer: Color(0xFFDDD6FE)), // violet
      LustrousCategoryColor(container: Color(0xFF134E4A), onContainer: Color(0xFF99F6E4)), // teal
    ],
  );

  static LustrousColors of(BuildContext context) {
    final ext = Theme.of(context).extension<LustrousColors>();
    if (ext != null) return ext;
    return Theme.of(context).brightness == Brightness.dark ? dark : light;
  }

  LustrousCategoryColor speakerColorFor(int speakerId) {
    return speakerPalette[speakerId.abs() % speakerPalette.length];
  }

  @override
  LustrousColors copyWith({
    Color? positive,
    Color? positiveContainer,
    Color? onPositiveContainer,
    Color? warning,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? danger,
    Color? dangerContainer,
    Color? onDangerContainer,
    List<LustrousCategoryColor>? speakerPalette,
  }) {
    return LustrousColors(
      positive: positive ?? this.positive,
      positiveContainer: positiveContainer ?? this.positiveContainer,
      onPositiveContainer: onPositiveContainer ?? this.onPositiveContainer,
      warning: warning ?? this.warning,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
      danger: danger ?? this.danger,
      dangerContainer: dangerContainer ?? this.dangerContainer,
      onDangerContainer: onDangerContainer ?? this.onDangerContainer,
      speakerPalette: speakerPalette ?? this.speakerPalette,
    );
  }

  @override
  LustrousColors lerp(ThemeExtension<LustrousColors>? other, double t) {
    if (other is! LustrousColors) return this;
    final len = speakerPalette.length < other.speakerPalette.length
        ? speakerPalette.length
        : other.speakerPalette.length;
    return LustrousColors(
      positive: Color.lerp(positive, other.positive, t)!,
      positiveContainer: Color.lerp(positiveContainer, other.positiveContainer, t)!,
      onPositiveContainer: Color.lerp(onPositiveContainer, other.onPositiveContainer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningContainer: Color.lerp(warningContainer, other.warningContainer, t)!,
      onWarningContainer: Color.lerp(onWarningContainer, other.onWarningContainer, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerContainer: Color.lerp(dangerContainer, other.dangerContainer, t)!,
      onDangerContainer: Color.lerp(onDangerContainer, other.onDangerContainer, t)!,
      speakerPalette: [
        for (int i = 0; i < len; i++)
          LustrousCategoryColor.lerp(speakerPalette[i], other.speakerPalette[i], t),
      ],
    );
  }
}

/// Builds Light (Mineral Slate) and Dark (Obsidian Slate) Material 3 themes
/// aligned with `@ghchinoy/lustrous-lit`.
class LustrousTheme {
  static ThemeData light() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xFF1D4ED8), // Lustrous Sapphire
      onPrimary: Color(0xFFFFFFFF),
      primaryContainer: Color(0xFFDBEAFE),
      onPrimaryContainer: Color(0xFF1E3A8A),
      secondary: Color(0xFF2563EB),
      onSecondary: Color(0xFFFFFFFF),
      secondaryContainer: Color(0xFFE0E7FF),
      onSecondaryContainer: Color(0xFF1E1B4B),
      tertiary: Color(0xFF0F766E), // Mineral Teal
      onTertiary: Color(0xFFFFFFFF),
      tertiaryContainer: Color(0xFFCCFBF1),
      onTertiaryContainer: Color(0xFF134E4A),
      error: Color(0xFFB91C1C),
      onError: Color(0xFFFFFFFF),
      errorContainer: Color(0xFFFEE2E2),
      onErrorContainer: Color(0xFF991B1B),
      surface: Color(0xFFFFFFFF),
      onSurface: Color(0xFF0F172A),
      onSurfaceVariant: Color(0xFF475569),
      surfaceContainerLowest: Color(0xFFFFFFFF),
      surfaceContainerLow: Color(0xFFF8FAFC),
      surfaceContainer: Color(0xFFF1F5F9),
      surfaceContainerHigh: Color(0xFFE2E8F0),
      surfaceContainerHighest: Color(0xFFCBD5E1),
      outline: Color(0xFF64748B),
      outlineVariant: Color(0xFFCBD5E1),
      shadow: Color(0xFF0F172A),
      scrim: Color(0x520F172A),
      inverseSurface: Color(0xFF111827),
      onInverseSurface: Color(0xFFF1F5F9),
      inversePrimary: Color(0xFF93C5FD),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFFF8FAFC),
      cardTheme: CardThemeData(
        color: scheme.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFF8FAFC),
        foregroundColor: Color(0xFF0F172A),
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant),
      extensions: const [LustrousColors.light],
    );
  }

  static ThemeData dark() {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFF93C5FD), // Lustrous Sapphire (dark)
      onPrimary: Color(0xFF0C2461),
      primaryContainer: Color(0xFF1E3A8A),
      onPrimaryContainer: Color(0xFFDBEAFE),
      secondary: Color(0xFF60A5FA),
      onSecondary: Color(0xFF081226),
      secondaryContainer: Color(0xFF1E2B58),
      onSecondaryContainer: Color(0xFFE0E7FF),
      tertiary: Color(0xFF5EEAD4), // Mineral Teal (dark)
      onTertiary: Color(0xFF042F2E),
      tertiaryContainer: Color(0xFF115E59),
      onTertiaryContainer: Color(0xFFCCFBF1),
      error: Color(0xFFF87171),
      onError: Color(0xFF450A0A),
      errorContainer: Color(0xFF7F1D1D),
      onErrorContainer: Color(0xFFFEE2E2),
      surface: Color(0xFF111827), // Obsidian Slate
      onSurface: Color(0xFFF1F5F9),
      onSurfaceVariant: Color(0xFF94A3B8),
      surfaceContainerLowest: Color(0xFF0B0F17),
      surfaceContainerLow: Color(0xFF151D2E),
      surfaceContainer: Color(0xFF1A2336),
      surfaceContainerHigh: Color(0xFF232F46),
      surfaceContainerHighest: Color(0xFF2E3C56),
      outline: Color(0xFF8496AE),
      outlineVariant: Color(0xFF334155),
      shadow: Color(0xFF000000),
      scrim: Color(0x8F000000),
      inverseSurface: Color(0xFFF8FAFC),
      onInverseSurface: Color(0xFF0F172A),
      inversePrimary: Color(0xFF1D4ED8),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: const Color(0xFF0B0F17),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainer,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0B0F17),
        foregroundColor: Color(0xFFF1F5F9),
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant),
      extensions: const [LustrousColors.dark],
    );
  }
}
