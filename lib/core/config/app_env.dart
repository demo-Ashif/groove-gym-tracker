/// Build flavors (ADR §16). Selected by entrypoint —
/// `lib/main_dev.dart` → `bootstrap(AppEnvironment.dev)` — so a run is
/// `flutter run -t lib/main_dev.dart --flavor dev`.
enum AppEnvironment { dev, stg, prod }

/// Static holder for the active flavor. Set once in `bootstrap()` before
/// anything else runs; read-only everywhere else.
///
/// Prefer injecting `AppConfig` over reading this directly — this exists for
/// the handful of places that run before DI (error handlers, logging).
abstract final class AppEnv {
  static AppEnvironment _current = AppEnvironment.dev;

  static AppEnvironment get current => _current;

  static void set(AppEnvironment env) => _current = env;
}

extension AppEnvironmentX on AppEnvironment {
  /// Application ID (ADR §1.2). Permanent once published — Android will never
  /// let it change.
  String get applicationId => switch (this) {
    AppEnvironment.dev => 'lab.aether.groove.dev',
    AppEnvironment.stg => 'lab.aether.groove.stg',
    AppEnvironment.prod => 'lab.aether.groove',
  };

  /// Home-screen name. Three flavors install side by side, so the launcher
  /// has to distinguish them.
  String get displayName => switch (this) {
    AppEnvironment.dev => 'Groove Dev',
    AppEnvironment.stg => 'Groove Stg',
    AppEnvironment.prod => 'Groove',
  };

  /// Supabase project (ADR §16). Dev and staging share `groove-dev`; a debug
  /// build must never point at prod data.
  ///
  /// Both values are public by design and protected by RLS, which is why they
  /// can live in `env/*.json` and be passed with `--dart-define-from-file`.
  /// The Anthropic key is not here and never will be — it stays in the
  /// `parse-plan` Edge Function (ADR §5.3).
  String get supabaseUrl => switch (this) {
    AppEnvironment.dev ||
    AppEnvironment.stg => const String.fromEnvironment('SUPABASE_URL_DEV'),
    AppEnvironment.prod => const String.fromEnvironment('SUPABASE_URL_PROD'),
  };

  String get supabaseAnonKey => switch (this) {
    AppEnvironment.dev ||
    AppEnvironment.stg => const String.fromEnvironment('SUPABASE_ANON_KEY_DEV'),
    AppEnvironment.prod => const String.fromEnvironment(
      'SUPABASE_ANON_KEY_PROD',
    ),
  };

  /// Sentry is off in dev (ADR §16) — local stack traces are more useful than
  /// a remote issue tracker full of your own hot reloads.
  bool get enableCrashReporting => this != AppEnvironment.dev;

  bool get isDev => this == AppEnvironment.dev;
  bool get isStg => this == AppEnvironment.stg;
  bool get isProd => this == AppEnvironment.prod;
}
