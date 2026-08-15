import 'package:flutter/material.dart';

/// Groove's colour tokens (ADR §13.2), mapped onto Material 3's
/// [ColorScheme] slots.
///
/// **Why not `ColorScheme.fromSeed`.** The design is dark-first, editorial and
/// near-monochrome with exactly one accent. Material's tonal generator would
/// take `#D6FF3E`, pull the chroma down through the mid tones and hand back a
/// set of olive greens spread across surfaces the design wants neutral. The
/// ADR specifies eleven literal tokens per brightness, so that is what this
/// builds; everything else is a documented derivation from them.
///
/// Every value below traces to an ADR §13.2 row. Change them there and here
/// together.
abstract final class GroovePalette {
  // --- ADR §13.2 tokens, dark ----------------------------------------------
  static const darkBackground = Color(0xFF0B0C0E);
  static const darkSurface = Color(0xFF16181C);
  static const darkSurfaceRaised = Color(0xFF1E2126);
  static const darkOutline = Color(0xFF2A2E35);
  static const darkTextPrimary = Color(0xFFF5F6F7);
  static const darkTextSecondary = Color(0xFF9BA1AB);
  static const darkAccent = Color(0xFFD6FF3E);
  static const darkAccentMuted = Color(0xFF3A4416);
  static const darkSuccess = Color(0xFF4ADE80);
  static const darkWarning = Color(0xFFFBBF24);
  static const darkDanger = Color(0xFFF87171);

  // --- ADR §13.2 tokens, light ---------------------------------------------
  static const lightBackground = Color(0xFFFAFAF7);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceRaised = Color(0xFFF2F2EE);
  static const lightOutline = Color(0xFFE2E2DC);
  static const lightTextPrimary = Color(0xFF101114);
  static const lightTextSecondary = Color(0xFF5F6570);
  static const lightAccent = Color(0xFF4B6B00);
  static const lightAccentMuted = Color(0xFFE7F5B0);
  static const lightSuccess = Color(0xFF15803D);
  static const lightWarning = Color(0xFFB45309);
  static const lightDanger = Color(0xFFB91C1C);

  static ColorScheme scheme(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  /// The hairline that separates a card from the page. Dark mode leans on
  /// surface *tone* (ADR §13.2) so the border is barely-there; light mode uses
  /// the outline token directly.
  static Color hairline(Brightness brightness) => brightness == Brightness.dark
      ? Colors.white.withValues(alpha: 0.05)
      : lightOutline;

  /// Dark is the default (gym lighting, evening sessions — ADR §13.1).
  ///
  /// Surface ramp: `background` is the page, `surfaceContainer` is the card
  /// (`surface` token), `surfaceContainerHigh` is a sheet or an active row
  /// (`surfaceRaised` token). The lowest/highest steps are extrapolated one
  /// step further out so M3 components that reach for them stay inside the
  /// same tonal family instead of falling back to Material's purple-tinted
  /// greys.
  static const dark = ColorScheme(
    brightness: Brightness.dark,
    primary: darkAccent,
    // Near-black rather than pure black: on a lime fill, pure black reads as
    // a hole. 16.2:1 either way.
    onPrimary: Color(0xFF101403),
    primaryContainer: darkAccentMuted,
    onPrimaryContainer: Color(0xFFE8FFA8),
    // The near-monochrome half of the design. Secondary carries structure —
    // chips, inactive tabs — and deliberately has no hue of its own.
    secondary: darkTextSecondary,
    onSecondary: Color(0xFF16181C),
    secondaryContainer: darkOutline,
    onSecondaryContainer: Color(0xFFE4E7EB),
    // Derived, not specified: a desaturated accent for the rare M3 component
    // that reaches for tertiary. Never used as a brand colour — the design
    // has exactly one accent.
    tertiary: Color(0xFFB9CE7A),
    onTertiary: Color(0xFF1B2600),
    tertiaryContainer: Color(0xFF2E3A12),
    onTertiaryContainer: Color(0xFFDCEFB4),
    error: darkDanger,
    onError: Color(0xFF3B0A0A),
    errorContainer: Color(0xFF4A1717),
    onErrorContainer: Color(0xFFFFDAD6),
    surface: darkBackground,
    onSurface: darkTextPrimary,
    onSurfaceVariant: darkTextSecondary,
    surfaceDim: darkBackground,
    surfaceBright: Color(0xFF262A31),
    surfaceContainerLowest: Color(0xFF08090B),
    surfaceContainerLow: Color(0xFF101216),
    surfaceContainer: darkSurface,
    surfaceContainerHigh: darkSurfaceRaised,
    surfaceContainerHighest: Color(0xFF262A31),
    // ADR gives one `outline` token, which is the hairline. M3 wants two:
    // `outlineVariant` for dividers and chip borders (the ADR value) and a
    // brighter `outline` for borders that must actually be seen — a focused
    // field, a disabled control's edge.
    outline: Color(0xFF3D434C),
    outlineVariant: darkOutline,
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: darkTextPrimary,
    onInverseSurface: darkSurface,
    inversePrimary: lightAccent,
    surfaceTint: darkAccent,
  );

  static const light = ColorScheme(
    brightness: Brightness.light,
    primary: lightAccent,
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: lightAccentMuted,
    onPrimaryContainer: Color(0xFF1B2600),
    secondary: lightTextSecondary,
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: lightOutline,
    onSecondaryContainer: Color(0xFF1B1D22),
    tertiary: Color(0xFF6B8A2E),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFDCEFB4),
    onTertiaryContainer: Color(0xFF22300A),
    error: lightDanger,
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFFDAD6),
    onErrorContainer: Color(0xFF410002),
    surface: lightBackground,
    onSurface: lightTextPrimary,
    onSurfaceVariant: lightTextSecondary,
    surfaceDim: Color(0xFFEAEAE4),
    surfaceBright: Color(0xFFFFFFFF),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFFDFDFB),
    surfaceContainer: lightSurface,
    surfaceContainerHigh: lightSurfaceRaised,
    surfaceContainerHighest: Color(0xFFEAEAE4),
    outline: Color(0xFFC6C6BF),
    outlineVariant: lightOutline,
    // Tinted with the page's warm ink rather than neutral grey — a grey
    // shadow under a warm surface is the most common reason a screen reads as
    // cheap.
    shadow: lightTextPrimary,
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFF16181C),
    onInverseSurface: Color(0xFFF5F6F7),
    inversePrimary: darkAccent,
    surfaceTint: lightAccent,
  );
}
