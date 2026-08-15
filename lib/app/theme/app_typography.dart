import 'package:flutter/material.dart';

/// Groove's type scale (ADR §13.3), built on Outfit.
///
/// Two things are load-bearing here.
///
/// **Tabular figures, everywhere.** A tracker is a wall of numbers that
/// change in place — a weight stepper, a rest countdown, a tonnage total.
/// With proportional digits every one of those visibly jitters as it ticks.
/// Outfit ships a `tnum` feature, so it is applied to every slot rather than
/// left to each widget to remember.
///
/// **Explicit sizes, not `TextTheme.apply`.** The ADR pins six sizes; deriving
/// them from Material's defaults would land near-but-not-on those numbers and
/// the screens would drift apart over time.
abstract final class AppTypography {
  static const fontFamily = 'Outfit';

  /// Digits stay in their columns. Applied to every slot below; use this
  /// helper for any style built outside the [TextTheme].
  static const tabular = [FontFeature.tabularFigures()];

  static TextStyle numeric(TextStyle style) =>
      style.copyWith(fontFeatures: tabular);

  static TextTheme textTheme(Color onSurface) {
    return TextTheme(
      // `display` — the big stats: "78.4 kg", a rest countdown, a phase
      // report's headline number.
      displayLarge: _style(48, FontWeight.w600, letterSpacing: -2),
      displayMedium: _style(40, FontWeight.w600, letterSpacing: -1.5),
      displaySmall: _style(34, FontWeight.w600, letterSpacing: -1.2),

      // Derived from the `display`/`titleLarge` rows: the steps between 34 and
      // 24 that page headers and hero cards need.
      headlineLarge: _style(30, FontWeight.w700, letterSpacing: -1),
      headlineMedium: _style(27, FontWeight.w700, letterSpacing: -0.8),
      headlineSmall: _style(24, FontWeight.w700, letterSpacing: -0.5),

      // `titleLarge` — screen titles.
      titleLarge: _style(24, FontWeight.w600, letterSpacing: -0.4),
      // `titleMedium` — card headers, exercise names.
      titleMedium: _style(18, FontWeight.w600, letterSpacing: -0.2),
      titleSmall: _style(15, FontWeight.w600),

      // `body` — 15/400, line height 1.45.
      bodyLarge: _style(15, FontWeight.w400, height: 1.45),
      bodyMedium: _style(14, FontWeight.w400, height: 1.45),
      bodySmall: _style(13, FontWeight.w400, height: 1.4),

      // `label` — chips, tabs. Also the `mono` row: same 13/500 tabular, and
      // since every slot carries `tnum` there is no separate mono style to
      // forget to apply.
      labelLarge: _style(13, FontWeight.w500, letterSpacing: 0.2),
      labelMedium: _style(12, FontWeight.w500, letterSpacing: 0.2),
      labelSmall: _style(11, FontWeight.w500, letterSpacing: 0.4),
    ).apply(bodyColor: onSurface, displayColor: onSurface);
  }

  static TextStyle _style(
    double size,
    FontWeight weight, {
    double? letterSpacing,
    double? height,
  }) {
    return TextStyle(
      fontFamily: fontFamily,
      fontSize: size,
      fontWeight: weight,
      letterSpacing: letterSpacing,
      height: height,
      fontFeatures: tabular,
    );
  }
}
