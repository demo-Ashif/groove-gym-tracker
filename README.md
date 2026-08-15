# Groove

*Follow the plan. See the line move.*

Turns a coach-written training plan into a day-by-day checklist you tap through
at the gym, and records what you actually did against what was prescribed.
Offline-first: the device is the source of truth.

Design and architecture: [`docs/groove_adr.md`](docs/groove_adr.md).

## Running

Three flavors install side by side (ADR §16). Each has its own entrypoint, so
the Dart-side environment and the native application ID always agree.

```bash
flutter run -t lib/main_dev.dart  --flavor dev  --dart-define-from-file=env/dev.json
flutter run -t lib/main_stg.dart  --flavor stg  --dart-define-from-file=env/stg.json
flutter run -t lib/main_prod.dart --flavor prod --dart-define-from-file=env/prod.json
```

| Flavor | Application ID | Home-screen name |
|---|---|---|
| dev | `lab.aether.groove.dev` | Groove Dev |
| stg | `lab.aether.groove.stg` | Groove Stg |
| prod | `lab.aether.groove` | Groove |

## Code generation

Both generators write gitignored output, so a fresh clone needs them before
`analyze` or `test`:

```bash
flutter pub get
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
