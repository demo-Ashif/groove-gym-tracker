// Default entrypoint for local development — the dev environment.
//
// dev and prod share one application ID and one native build; the environment
// is Dart-side config, selected by entrypoint and compiled in from
// `core/config/app_env.dart`. There are no dart-defines and no `env/*.json`.
//
//   fvm flutter run -t lib/main_dev.dart
//   fvm flutter run -t lib/main_prod.dart
//
// iOS only, for running from Xcode rather than the CLI: the Dev and Prod
// schemes select the Debug-Dev / Debug-Prod build configurations, whose
// xcconfig sets FLUTTER_TARGET to the matching entrypoint. Android defines no
// product flavors, so `--flavor` is not usable from the CLI.

import 'bootstrap.dart';
import 'core/config/app_env.dart';

Future<void> main() => bootstrap(AppEnvironment.dev);
