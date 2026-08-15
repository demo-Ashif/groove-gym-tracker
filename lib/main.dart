// Default entrypoint for local development — the dev flavor.
//
// Run another flavor with its own entrypoint so the Dart-side environment and
// the native application ID always agree:
//   fvm flutter run -t lib/main_dev.dart  --flavor dev
//   fvm flutter run -t lib/main_stg.dart  --flavor stg
//   fvm flutter run -t lib/main_prod.dart --flavor prod

import 'bootstrap.dart';
import 'core/config/app_env.dart';

Future<void> main() => bootstrap(AppEnvironment.dev);
