import 'dart:ui';

import 'package:flutter/material.dart';

import 'app/app.dart';
import 'core/config/app_env.dart';
import 'core/di/injector.dart';
import 'core/logging/app_logger.dart';

/// App entry pipeline, called from the per-flavor entrypoints
/// (`main_dev.dart`, `main_stg.dart`, `main_prod.dart`).
///
/// Order matters:
/// 1. Pin the flavor — everything downstream reads it.
/// 2. Install global error handlers *before* anything can throw.
/// 3. DI, which opens the preference store so the first frame is already
///    themed, localized and on the right tab.
/// 4. `runApp`.
///
/// Anything genuinely heavy — Drift migrations, the anonymous Supabase
/// sign-in, a sync pass — belongs after `runApp`, behind the UI. Startup must
/// not wait on the network: a dead connection has to be invisible
/// (ADR §2.1 principle 3).
Future<void> bootstrap(AppEnvironment env) async {
  WidgetsFlutterBinding.ensureInitialized();

  AppEnv.set(env);

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    AppLogger.e(
      'FlutterError',
      error: details.exception,
      stackTrace: details.stack,
    );
  };

  // Errors from the engine and from unawaited futures on the root zone.
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    AppLogger.e('Uncaught error', error: error, stackTrace: stackTrace);
    return true;
  };

  await configureDependencies(env);

  AppLogger.i('Groove starting — flavor: ${env.name}', tag: 'BOOT');

  runApp(const App());
}
