import 'app_env.dart';

/// Immutable app configuration, derived from the [AppEnvironment] passed to
/// `bootstrap()`. Injected via DI — prefer `getIt<AppConfig>()` over reading
/// [AppEnv] directly so dependencies stay explicit and testable.
class AppConfig {
  const AppConfig({
    required this.env,
    required this.supabaseUrl,
    required this.supabaseAnonKey,
    required this.enableCrashReporting,
  });

  factory AppConfig.fromEnv(AppEnvironment env) => AppConfig(
    env: env,
    supabaseUrl: env.supabaseUrl,
    supabaseAnonKey: env.supabaseAnonKey,
    enableCrashReporting: env.enableCrashReporting,
  );

  /// Mirrors `pubspec.yaml`'s `version`. A literal rather than a
  /// `package_info_plus` lookup: it is rendered in one row on the Profile tab,
  /// and a plugin plus an async read is not worth it for that. Bump alongside
  /// the pubspec.
  static const version = '0.1.0';

  final AppEnvironment env;

  /// Empty until the Supabase project exists (ADR roadmap Phase 2). The sync
  /// layer must treat empty as "remote disabled" and keep working — the
  /// device is the source of truth, so no backend is a supported state, not
  /// an error.
  final String supabaseUrl;
  final String supabaseAnonKey;

  bool get hasRemote => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  final bool enableCrashReporting;
}
