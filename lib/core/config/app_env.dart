/// Build environments. Not Android/iOS build flavors — there is a single
/// native build variant and a single application ID. An environment is
/// Dart-side config only, selected by entrypoint —
/// `lib/main_dev.dart` → `bootstrap(AppEnvironment.dev)` — with its values
/// supplied by `--dart-define-from-file=env/dev.json`.
enum AppEnvironment { dev, prod }

/// Static holder for the active environment. Set once in `bootstrap()` before
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
  /// Supabase project (ADR §16). A debug build must never point at prod data,
  /// which is why the two environments read different dart-define keys rather
  /// than one key with a swapped value.
  ///
  /// Both values are public by design and protected by RLS, which is why they
  /// can live in `env/*.json` and be passed with `--dart-define-from-file`.
  /// The Anthropic key is not here and never will be — it stays in the
  /// `parse-plan` Edge Function (ADR §5.3).
  String get supabaseUrl => switch (this) {
    AppEnvironment.dev => const String.fromEnvironment('SUPABASE_URL_DEV'),
    AppEnvironment.prod => const String.fromEnvironment('SUPABASE_URL_PROD'),
  };

  String get supabaseAnonKey => switch (this) {
    AppEnvironment.dev => const String.fromEnvironment('SUPABASE_ANON_KEY_DEV'),
    AppEnvironment.prod => const String.fromEnvironment(
      'SUPABASE_ANON_KEY_PROD',
    ),
  };

  /// Sentry is off in dev (ADR §16) — local stack traces are more useful than
  /// a remote issue tracker full of your own hot reloads.
  bool get enableCrashReporting => this != AppEnvironment.dev;

  bool get isDev => this == AppEnvironment.dev;
  bool get isProd => this == AppEnvironment.prod;
}
