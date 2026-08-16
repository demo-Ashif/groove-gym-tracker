// Default entrypoint for local development — the dev environment.
//
// There are no build flavors: dev and prod share one application ID and one
// native build. The environment is Dart-side config, picked by entrypoint and
// fed by --dart-define-from-file:
//   fvm flutter run -t lib/main_dev.dart  --dart-define-from-file=env/dev.json
//   fvm flutter run -t lib/main_prod.dart --dart-define-from-file=env/prod.json

import 'bootstrap.dart';
import 'core/config/app_env.dart';

Future<void> main() => bootstrap(AppEnvironment.dev);
