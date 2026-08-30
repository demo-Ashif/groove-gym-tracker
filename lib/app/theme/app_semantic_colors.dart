import 'package:flutter/material.dart';

import 'groove_palette.dart';

/// Colours that carry meaning the M3 [ColorScheme] has no slot for — success
/// (a PR), warning (behind on the plan) and info. Registered as a
/// [ThemeExtension] so they resolve per-brightness like every other theme
/// colour and can never be hardcoded at a call site.
///
/// "Danger" deliberately isn't here: that's `ColorScheme.error`, which the
/// palette already points at the ADR's `danger` token — the colour a
/// skipped-for-pain set is drawn in.
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.info,
    required this.onInfo,
    required this.infoContainer,
    required this.onInfoContainer,
  });

  factory AppSemanticColors.of(Brightness brightness) =>
      brightness == Brightness.dark ? _dark : _light;

  /// Lookup that cannot fail: falls back to the brightness-matched defaults
  /// if the extension somehow isn't registered, so a call site can never
  /// crash on a null theme extension.
  static AppSemanticColors from(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<AppSemanticColors>() ??
        AppSemanticColors.of(theme.brightness);
  }

  /// ADR §13.2 `success` — PRs, completed sets that beat target.
  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;

  /// ADR §13.2 `warning` — behind the plan, missed sessions.
  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color onWarningContainer;

  /// Not an ADR token. Reserved for neutral advisories (sync notices, "3 more
  /// sessions until this chart means something") where warning would overstate
  /// the problem.
  final Color info;
  final Color onInfo;
  final Color infoContainer;
  final Color onInfoContainer;

  static const _dark = AppSemanticColors(
    success: GroovePalette.darkSuccess,
    onSuccess: Color(0xFF052E16),
    successContainer: Color(0xFF14371F),
    onSuccessContainer: Color(0xFFB6F0C6),
    warning: GroovePalette.darkWarning,
    onWarning: Color(0xFF3A2606),
    warningContainer: Color(0xFF4A3410),
    onWarningContainer: Color(0xFFFFE3A3),
    info: Color(0xFF93C5FD),
    onInfo: Color(0xFF0A2540),
    infoContainer: Color(0xFF1B3350),
    onInfoContainer: Color(0xFFD6E6FF),
  );

  static const _light = AppSemanticColors(
    success: GroovePalette.lightSuccess,
    onSuccess: Color(0xFFFFFFFF),
    successContainer: Color(0xFFDCF3E3),
    onSuccessContainer: Color(0xFF04310F),
    warning: GroovePalette.lightWarning,
    onWarning: Color(0xFFFFFFFF),
    warningContainer: Color(0xFFFCEBD3),
    onWarningContainer: Color(0xFF3E2003),
    info: Color(0xFF1D4ED8),
    onInfo: Color(0xFFFFFFFF),
    infoContainer: Color(0xFFDEE7FB),
    onInfoContainer: Color(0xFF0A1F52),
  );

  @override
  AppSemanticColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? info,
    Color? onInfo,
    Color? infoContainer,
    Color? onInfoContainer,
  }) {
    return AppSemanticColors(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
      info: info ?? this.info,
      onInfo: onInfo ?? this.onInfo,
      infoContainer: infoContainer ?? this.infoContainer,
      onInfoContainer: onInfoContainer ?? this.onInfoContainer,
    );
  }

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) {
    if (other is! AppSemanticColors) return this;
    return AppSemanticColors(
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      successContainer: Color.lerp(
        successContainer,
        other.successContainer,
        t,
      )!,
      onSuccessContainer: Color.lerp(
        onSuccessContainer,
        other.onSuccessContainer,
        t,
      )!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      warningContainer: Color.lerp(
        warningContainer,
        other.warningContainer,
        t,
      )!,
      onWarningContainer: Color.lerp(
        onWarningContainer,
        other.onWarningContainer,
        t,
      )!,
      info: Color.lerp(info, other.info, t)!,
      onInfo: Color.lerp(onInfo, other.onInfo, t)!,
      infoContainer: Color.lerp(infoContainer, other.infoContainer, t)!,
      onInfoContainer: Color.lerp(onInfoContainer, other.onInfoContainer, t)!,
    );
  }
}

/// A named colour role a component can be tinted with, resolved against the
/// active [ColorScheme] + [AppSemanticColors]. Lets a widget take
/// `tone: AppTone.success` instead of a raw [Color], so nothing breaks in the
/// other brightness.
enum AppTone {
  /// The accent. Primary action, completed sets, the active chart series.
  accent,

  /// Structural, hueless. Inactive chips, secondary metadata.
  neutral,
  success,
  info,
  warning,

  /// Pain flags, skipped-for-pain sets, destructive actions.
  danger;

  /// (container, onContainer) pair for filled chips, icon wells and tiles.
  ({Color container, Color onContainer}) container(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final semantic = AppSemanticColors.from(context);

    return switch (this) {
      AppTone.accent => (
        container: scheme.primaryContainer,
        onContainer: scheme.onPrimaryContainer,
      ),
      AppTone.neutral => (
        container: scheme.surfaceContainerHigh,
        onContainer: scheme.onSurfaceVariant,
      ),
      AppTone.success => (
        container: semantic.successContainer,
        onContainer: semantic.onSuccessContainer,
      ),
      AppTone.info => (
        container: semantic.infoContainer,
        onContainer: semantic.onInfoContainer,
      ),
      AppTone.warning => (
        container: semantic.warningContainer,
        onContainer: semantic.onWarningContainer,
      ),
      AppTone.danger => (
        container: scheme.errorContainer,
        onContainer: scheme.onErrorContainer,
      ),
    };
  }

  /// Solid colour for progress arcs, bars and emphasis text.
  Color accentColor(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final semantic = AppSemanticColors.from(context);

    return switch (this) {
      AppTone.accent => scheme.primary,
      AppTone.neutral => scheme.onSurfaceVariant,
      AppTone.success => semantic.success,
      AppTone.info => semantic.info,
      AppTone.warning => semantic.warning,
      AppTone.danger => scheme.error,
    };
  }
}
