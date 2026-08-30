import 'package:flutter/material.dart';

/// Design tokens — the single source of truth for spacing, radii, durations
/// and motion. Widgets pull from here instead of inventing magic numbers, so
/// a restyle is a change in this file rather than a sweep of the codebase.
///
/// Values are ADR §13.4 and §14.1 verbatim.

/// 4pt scale (ADR §13.4).
abstract final class AppSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  /// The page gutter. Deliberately off the 4pt scale's usual 16/24 step —
  /// ADR §13.4 pins it at 20 so a card's shadow has room without the content
  /// feeling cramped.
  static const double gutter = 20;
}

/// Radii (ADR §13.4): 8 chips, 16 cards, 28 sheets and FABs.
abstract final class AppRadius {
  static const double chip = 8;
  static const double sm = 8;
  static const double md = 12;

  /// Cards.
  static const double lg = 16;

  /// Sheets, FAB, hero surfaces.
  static const double xl = 28;
  static const double full = 999;

  static const BorderRadius smAll = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdAll = BorderRadius.all(Radius.circular(md));
  static const BorderRadius lgAll = BorderRadius.all(Radius.circular(lg));
  static const BorderRadius xlAll = BorderRadius.all(Radius.circular(xl));
  static const BorderRadius fullAll = BorderRadius.all(Radius.circular(full));
}

/// Motion durations (ADR §14.1). Pair each with its curve in [AppMotion] —
/// duration says how long, curve says how it feels.
abstract final class AppDurations {
  /// Chip press, colour change.
  static const micro = Duration(milliseconds: 120);

  /// Expand/collapse, cross-fade, reorder. The default for a state change.
  static const base = Duration(milliseconds: 220);

  /// Set-complete check, PR badge.
  static const emphasis = Duration(milliseconds: 380);

  /// Route transitions.
  static const page = Duration(milliseconds: 300);

  /// Chart series draw-in — once per appearance, never per rebuild.
  static const chart = Duration(milliseconds: 450);
}

/// Motion curves (ADR §14.1).
abstract final class AppMotion {
  /// Pairs with [AppDurations.micro].
  static const Curve micro = Curves.easeOut;

  /// Pairs with [AppDurations.base], [AppDurations.page] and
  /// [AppDurations.chart]. The workhorse.
  static const Curve standard = Curves.easeOutCubic;

  /// Pairs with [AppDurations.emphasis]. Overshoot — reserved for the set
  /// chip completing and a PR landing. Anywhere else it reads as a toy.
  static const Curve emphasis = Curves.easeOutBack;
}

abstract final class AppSizes {
  /// Minimum touch target (Material accessibility, ADR checklist).
  static const double minTapTarget = 48;
  static const double buttonHeight = 52;

  /// Text scale is clamped to this range app-wide: past 1.4 the set chips in
  /// the active-session grid break their row (ADR §13.3).
  static const double minTextScale = 0.85;
  static const double maxTextScale = 1.4;

  /// Max content width for the main scrollable columns on tablet, so a
  /// 12-inch iPad doesn't render a 900px-wide line of body text.
  static const double maxContentWidth = 640;
}

/// Soft, low-opacity elevation (ADR §13.2: shadows ≤12% opacity, large blur,
/// no visible offset; dark mode separates surfaces by tone instead).
abstract final class AppElevation {
  static List<BoxShadow> soft(ColorScheme scheme) {
    final isDark = scheme.brightness == Brightness.dark;
    return [
      BoxShadow(
        color: scheme.shadow.withValues(alpha: isDark ? 0.24 : 0.06),
        blurRadius: 18,
        offset: const Offset(0, 4),
        spreadRadius: -4,
      ),
    ];
  }

  static List<BoxShadow> lifted(ColorScheme scheme) {
    final isDark = scheme.brightness == Brightness.dark;
    return [
      BoxShadow(
        color: scheme.shadow.withValues(alpha: isDark ? 0.32 : 0.10),
        blurRadius: 28,
        offset: const Offset(0, 10),
        spreadRadius: -6,
      ),
    ];
  }

  /// Accent halo for the few surfaces meant to look lit — the active set
  /// chip, a new PR. Two layers on purpose: a wide soft halo in the element's
  /// own colour plus a tight contact shadow that keeps it anchored. A single
  /// large blur reads as fog; the pair reads as depth.
  static List<BoxShadow> glow(
    Color color, {
    required Brightness brightness,
    double strength = 1,
  }) {
    final isDark = brightness == Brightness.dark;
    return [
      BoxShadow(
        color: color.withValues(alpha: (isDark ? 0.28 : 0.34) * strength),
        blurRadius: 24 * strength,
        offset: Offset(0, 8 * strength),
        spreadRadius: -6,
      ),
      BoxShadow(
        color: color.withValues(alpha: (isDark ? 0.16 : 0.20) * strength),
        blurRadius: 6 * strength,
        offset: Offset(0, 2 * strength),
        spreadRadius: -2,
      ),
    ];
  }
}
