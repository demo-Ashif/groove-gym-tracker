/// Build environments.
///
/// An environment is selected by entrypoint — `lib/main_dev.dart` calls
/// `bootstrap(AppEnvironment.dev)` — and its values are compiled in from the
/// constants below. There are no dart-defines and no `env/*.json`: the values
/// that vary are public by design (see [AppEnvironmentX.supabaseUrl]), so a
/// checked-in Dart constant is simpler to read, refactor and grep than a
/// build-time define, and it cannot be forgotten at the call site.
///
/// On iOS the entrypoint is wired to the Xcode scheme through per-flavour
/// build configurations — `ios/Flutter/Debug-Dev.xcconfig` and friends set
/// `FLUTTER_TARGET`, so the Dev and Prod schemes launch the matching
/// `main_*.dart` without any argument being passed by hand.
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

/// Per-environment values, compiled in.
///
/// Empty until the Supabase projects exist (ADR roadmap Phase 2). The sync
/// layer must treat an empty URL as "remote disabled" and keep working — the
/// device is the source of truth, so no backend is a supported state, not an
/// error.
///
/// **What may live here:** the Supabase project URL and anon key. Both are
/// public by design and protected by RLS, which is why they can be committed.
///
/// **What may never live here:** any service-role key or third-party API key.
/// Those stay server-side — a key in a shipped binary is an extracted key,
/// whatever supplies it.
abstract final class _Dev {
  static const supabaseUrl = '';
  static const supabaseAnonKey = '';
}

abstract final class _Prod {
  static const supabaseUrl = '';
  static const supabaseAnonKey = '';
}

extension AppEnvironmentX on AppEnvironment {
  /// Supabase project (ADR §16). A debug build must never point at prod data,
  /// which is why the two environments hold separate constants rather than one
  /// constant with a swapped value.
  String get supabaseUrl => switch (this) {
    AppEnvironment.dev => _Dev.supabaseUrl,
    AppEnvironment.prod => _Prod.supabaseUrl,
  };

  String get supabaseAnonKey => switch (this) {
    AppEnvironment.dev => _Dev.supabaseAnonKey,
    AppEnvironment.prod => _Prod.supabaseAnonKey,
  };

  /// Sentry is off in dev (ADR §16) — local stack traces are more useful than
  /// a remote issue tracker full of your own hot reloads.
  bool get enableCrashReporting => this != AppEnvironment.dev;

  bool get isDev => this == AppEnvironment.dev;
  bool get isProd => this == AppEnvironment.prod;
}
