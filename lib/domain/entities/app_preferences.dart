import 'package:equatable/equatable.dart';

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

  AppPreferences copyWith({
    AppThemeMode? themeMode,
    String? localeCode,
    bool clearLocaleCode = false,
    bool? hapticsEnabled,
    int? lastTabIndex,
  }) {
    return AppPreferences(
      themeMode: themeMode ?? this.themeMode,
      // A nullable field can't be cleared by passing null — that's
      // indistinguishable from "leave it alone" — so "follow the system" has
      // its own flag.
      localeCode: clearLocaleCode ? null : (localeCode ?? this.localeCode),
      hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
      lastTabIndex: lastTabIndex ?? this.lastTabIndex,
    );
  }

  @override
  List<Object?> get props => [
    themeMode,
    localeCode,
    hapticsEnabled,
    lastTabIndex,
  ];
}
