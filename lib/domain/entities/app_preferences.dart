import 'package:equatable/equatable.dart';

import '../values/body_metrics.dart';

/// Theme preference. Domain-owned, so the entity stays free of Flutter
/// imports; the presentation layer maps it to `ThemeMode`.
enum AppThemeMode {
  system,
  light,
  dark;

  static AppThemeMode fromId(String? id) => values.firstWhere(
    (mode) => mode.name == id,
    orElse: () => AppPreferences.defaultThemeMode,
  );
}

/// Device-local preferences (ADR §3: theme mode, locale override, last tab —
/// non-sensitive only, so `shared_preferences` rather than secure storage).
///
/// Equatable rather than freezed: this is a plain domain entity with four
/// scalars, and freezed is reserved for state and unions (ADR §3).
class AppPreferences extends Equatable {
  const AppPreferences({
    this.themeMode = defaultThemeMode,
    this.localeCode,
    this.hapticsEnabled = true,
    this.lastTabIndex = 0,
    this.unitSystem = UnitSystem.metric,
    this.gender = Gender.unspecified,
    this.heightCm,
  });

  /// Dark is the product default (ADR §13.1 — gym lighting, evening
  /// sessions), but `system` is the default *preference*: a user who has told
  /// their phone they want light mode should be believed.
  static const defaultThemeMode = AppThemeMode.system;

  final AppThemeMode themeMode;

  /// BCP-47 language code, or null to follow the system (ADR §12.1).
  final String? localeCode;

  /// Global haptics switch (ADR §14.3).
  final bool hapticsEnabled;

  /// Which bottom-nav branch to open on a cold start.
  final int lastTabIndex;

  /// Which units body measurements are shown and entered in. Display only —
  /// storage is always kg and cm.
  final UnitSystem unitSystem;

  final Gender gender;

  /// Height in **centimetres**, whatever the user typed it in. Null until they
  /// tell us; BMI stays blank rather than guessing.
  ///
  /// Lives here rather than in `check_ins` because height is a standing fact
  /// about a person, not a measurement taken on a date. Weight is the
  /// opposite, and lives in the check-in series.
  final double? heightCm;

  AppPreferences copyWith({
    AppThemeMode? themeMode,
    String? localeCode,
    bool clearLocaleCode = false,
    bool? hapticsEnabled,
    int? lastTabIndex,
    UnitSystem? unitSystem,
    Gender? gender,
    double? heightCm,
    bool clearHeightCm = false,
  }) {
    return AppPreferences(
      themeMode: themeMode ?? this.themeMode,
      // A nullable field can't be cleared by passing null — that's
      // indistinguishable from "leave it alone" — so "follow the system" has
      // its own flag.
      localeCode: clearLocaleCode ? null : (localeCode ?? this.localeCode),
      hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
      lastTabIndex: lastTabIndex ?? this.lastTabIndex,
      unitSystem: unitSystem ?? this.unitSystem,
      gender: gender ?? this.gender,
      heightCm: clearHeightCm ? null : (heightCm ?? this.heightCm),
    );
  }

  @override
  List<Object?> get props => [
    themeMode,
    localeCode,
    hapticsEnabled,
    lastTabIndex,
    unitSystem,
    gender,
    heightCm,
  ];
}
