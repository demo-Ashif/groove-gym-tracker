# Flavor configuration

Passed at build time (ADR §16):

```
flutter run -t lib/main_dev.dart  --flavor dev  --dart-define-from-file=env/dev.json
flutter run -t lib/main_stg.dart  --flavor stg  --dart-define-from-file=env/stg.json
flutter run -t lib/main_prod.dart --flavor prod --dart-define-from-file=env/prod.json
```

Empty until the Supabase projects exist (roadmap Phase 2). The app treats an
empty URL as "remote disabled" and runs fully offline, which is a supported
state — the device is the source of truth.

**What may live here:** the Supabase project URL and anon key. Both are public
by design and protected by RLS, which is why these files are committed.

**What may never live here:** the Anthropic key. It stays server-side in the
`parse-plan` Edge Function (ADR §5.3) — a key in a shipped binary is an
extracted key.
