# Environment configuration

Per-environment values (Supabase URL, anon key, and any future base URL),
passed at build time. There are no build flavors — the entrypoint selects the
environment and this file supplies its values:

```
flutter run -t lib/main_dev.dart  --dart-define-from-file=env/dev.json
flutter run -t lib/main_prod.dart --dart-define-from-file=env/prod.json
```

Keys are environment-suffixed (`SUPABASE_URL_DEV` / `SUPABASE_URL_PROD`) and
read through `AppEnvironmentX` in `lib/core/config/app_env.dart`. They must be
`String.fromEnvironment` constants, so a new key needs a getter there too — it
cannot be looked up dynamically.

Empty until the Supabase projects exist (roadmap Phase 2). The app treats an
empty URL as "remote disabled" and runs fully offline, which is a supported
state — the device is the source of truth.

**What may live here:** the Supabase project URL and anon key. Both are public
by design and protected by RLS, which is why these files are committed.

**What may never live here:** the Anthropic key. It stays server-side in the
`parse-plan` Edge Function (ADR §5.3) — a key in a shipped binary is an
extracted key.
