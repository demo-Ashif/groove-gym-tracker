# Groove

*Follow the plan. See the line move.*

Turns a coach-written training plan into a day-by-day checklist you tap through
at the gym, and records what you actually did against what was prescribed.
Offline-first: the device is the source of truth.

Design and architecture: [`docs/groove_adr.md`](docs/groove_adr.md).

## Running

One native build variant, one application ID (`lab.aether.groove`), one
home-screen app. `dev` and `prod` are Dart-side config only — the entrypoint
picks the environment and its values are compiled in from
`lib/core/config/app_env.dart`. No dart-defines, no `env/*.json`.

```bash
flutter run -t lib/main_dev.dart
flutter run -t lib/main_prod.dart
```

| Environment | Entrypoint | Values | Crash reporting |
|---|---|---|---|
| dev | `lib/main_dev.dart` | `app_env.dart` → `_Dev` | off |
| prod | `lib/main_prod.dart` | `app_env.dart` → `_Prod` | on |

Because there is one application ID, dev and prod overwrite each other on a
device — they do not install side by side.

### Running from Xcode (iOS only)

The **Dev** and **Prod** schemes select the `Debug-Dev` / `Debug-Prod` build
configurations, whose xcconfig (`ios/Flutter/Debug-Dev.xcconfig` and friends)
sets `FLUTTER_TARGET` to the matching entrypoint — so hitting Run in Xcode
launches the right one without passing `-t`. Each flavour has Debug, Release
and Profile configurations; Archive uses `Release-<flavour>`.

`FLUTTER_TARGET` lives **only** in those xcconfig files. Do not also set it in
the target's build settings — a target-level setting silently overrides the
xcconfig and the scheme stops mattering.

Android defines no product flavors, so `--flavor` works on iOS only and is not
used from the CLI.

### iOS dependencies: use `tool/pubget.sh`

iOS plugins are Swift Packages; CocoaPods is deintegrated and there is no
Podfile. The catch is that `flutter pub get` regenerates
`ios/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift`
with the Flutter tool's own minimum iOS version (13.0 as of 3.44), and only
raises it to the Runner target's 15.0 during a `flutter build/run ios`. Since
`file_picker_darwin` needs 14.0, a plain `pub get` followed by an Xcode build
fails package resolution:

```
The package product 'file-picker-darwin' requires minimum platform version
14.0 for the iOS platform, but this target supports 13.0
```

So run pub get through the wrapper, which repairs the manifest immediately:

```bash
tool/pubget.sh                   # instead of `flutter pub get`
```

The Dev and Prod schemes also carry a build pre-action that repairs it, but
Xcode resolves packages *before* pre-actions run — that safety net only takes
effect from the second build onwards. The wrapper is what keeps the first one
green.

## Code generation

Both generators write gitignored output, so a fresh clone needs them before
`analyze` or `test`:

```bash
tool/pubget.sh                   # see "iOS dependencies" above
flutter gen-l10n                 # lib/l10n/arb -> lib/l10n/generated
dart run build_runner build      # freezed / json_serializable
```

`flutter run` and `flutter build` run `gen-l10n` themselves (`generate: true`
in `pubspec.yaml`); `build_runner` is manual.

## What works today

Roadmap Phase 1 is complete: build a program (phases → days → blocks → exercises),
draw its week on a seven-chip strip, commit the schedule, then log a full session
from Today — tap-first, no keyboard — and finish with an RPE, an energy face and a
summary. Everything is on-device; the backup on the Profile tab is the only copy
that leaves it.

## Checks

```bash
flutter analyze
dart format --output=none --set-exit-if-changed lib test
flutter test
```

## Architecture in one paragraph

`flutter_bloc` for state, `get_it` for injection, `go_router` for navigation,
`drift` (SQLite) as the source of truth. Shared `lib/domain/` holds the entity
graph, the enums and the repository interfaces, and imports nothing from
Flutter, Drift or JSON. `lib/data/` holds the database, mappers and repository
implementations. UI is sliced per feature under `lib/features/*/presentation/`,
and a feature may import `domain`, `core` and `shared` — never `data`.
Cross-cutting infrastructure (design tokens, error types, logging, haptics)
lives in `lib/core/`; shared UI in `lib/shared/widgets/`.

The device is the source of truth. Supabase is durability and a future
multi-device path, never a dependency for logging a set.

No user-facing string is hardcoded: everything goes through
`lib/l10n/arb/app_en.arb`. English is the only locale today; adding another is
a translation job, not a refactor.
