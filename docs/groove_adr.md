# Groove — App Design & Architecture Document (ADR)

**Version:** 2.0 · **Date:** 16 Aug 2026 · **Platform:** Flutter (iOS 15+ / Android 8+, API 26)
**Bundle / Application ID:** `lab.aether.groove` · **Display name:** Groove
**Backend:** Supabase (Postgres + Storage + anonymous auth) · **Mode:** offline-first, single user, production-grade

> **Changes from v1.0:** Supabase added as the remote store behind an offline-first sync layer; all primary keys moved from `int` to client-generated `uuid`; full localization architecture added (English at launch, zero-refactor path to more locales); formal app identity, flavors and release engineering; production hardening (observability, testing, migrations, CI).

---

## Table of Contents

1. [App Identity & Package Naming](#1-app-identity--package-naming)
2. [Product Principles & Scope](#2-product-principles--scope)
3. [Technology Stack](#3-technology-stack)
4. [Domain Model](#4-domain-model)
5. [Backend Architecture (Supabase)](#5-backend-architecture-supabase)
6. [Sync Engine](#6-sync-engine)
7. [Plan Ingestion (Voice / Text / Paste)](#7-plan-ingestion-voice--text--paste)
8. [Scheduling & Cycles](#8-scheduling--cycles)
9. [The Logging Loop (tap-first, type-last)](#9-the-logging-loop-tap-first-type-last)
10. [Check-ins & Reassessment](#10-check-ins--reassessment)
11. [Insights & Analytics](#11-insights--analytics)
12. [Localization & Internationalization](#12-localization--internationalization)
13. [UI Design System](#13-ui-design-system)
14. [Motion & Haptics](#14-motion--haptics)
15. [Project Structure](#15-project-structure)
16. [Release Engineering & Flavors](#16-release-engineering--flavors)
17. [Observability, Testing & Quality Gates](#17-observability-testing--quality-gates)
18. [Privacy, Security & Data Safety](#18-privacy-security--data-safety)
19. [Roadmap](#19-roadmap)
20. [Suggestions & Open Decisions](#20-suggestions--open-decisions)

---

## 1. App Identity & Package Naming

### 1.1 App name

**Groove.** The app's job is answering *"did I hit the plan today, and is the line moving?"* — a rhythm question, not a workout-discovery question. Short, one syllable, warm, and it stays valid after the current 10-week program ends. It also echoes the coaching language in the plan itself ("grooving the pattern").

Alternates considered: Cadence (crowded by cycling apps), Onside (too sport-locked), Tally (reads accounting), Runrate (narrow).

**Tagline:** *Follow the plan. See the line move.*

### 1.2 Package / bundle identifier

You asked for an `aether.lab…` prefix. Reverse-DNS convention inverts the domain, so if the domain is **aether.lab**, the correct identifier is:

```
lab.aether.groove
```

Both Android and iOS accept `aether.lab.groove` too — it's syntactically legal — but it reads as "a domain named groove.lab.aether", which is wrong and looks amateurish in a crash report or an App Store listing. Use `lab.aether.groove`.

| Concern | Value |
|---|---|
| Android `applicationId` | `lab.aether.groove` |
| Android namespace / Kotlin package | `lab.aether.groove` |
| iOS `PRODUCT_BUNDLE_IDENTIFIER` | `lab.aether.groove` |
| Dev flavor | `lab.aether.groove.dev` (display name "Groove Dev") |
| Staging flavor | `lab.aether.groove.stg` (display name "Groove Stg") |
| Dart package (`pubspec.yaml` `name:`) | `groove` — imports become `package:groove/...` |
| Supabase project ref | `groove-prod` / `groove-dev` |
| Deep link scheme | `groove://` + universal link host if a domain exists |

**Hard rules:** `applicationId` is permanent once published — Android will never let you change it. Never rename the Dart package after scaffolding (it rewrites every import). Flavor suffixes must be appended to the *application ID*, never to the namespace, or R-class resolution breaks on Android.

### 1.3 Elevator pitch

Groove turns a coach-written training plan — pasted, dictated or typed — into a day-by-day checklist you tap through at the gym. It records what you actually did against what was prescribed, and rolls it into adherence, strength and body-composition trends filterable by day, week, month or training cycle.

---

## 2. Product Principles & Scope

### 2.1 Principles

1. **Plan-first, not workout-first.** Most gym apps make you assemble a session. Here the session already exists; the app's job is *diffing reality against it*. Every screen answers "planned vs actual".
2. **Tap-first, type-last.** Text entry is a failure mode. Target: **a full session logged in under 25 taps and zero keystrokes.**
3. **Offline-first, cloud-backed.** The device is the source of truth. Supabase is durability and future multi-device, never a dependency for logging a set. **A dead network must be invisible during a workout.**
4. **The gym is a hostile environment.** One hand, sweaty screen, 40-second rests, dodgy signal. Big hit targets, resumable state, nothing lost on a process kill.
5. **Production-grade from the first commit.** Flavors, migrations, tests and observability now — retrofitting them into a live personal app that grew is the expensive path.
6. **Fewer, deeper screens.** Four tabs. No settings maze.

### 2.2 Out of scope for v1

Social features, exercise video library, AI form checking, multi-user/teams, subscriptions, marketing onboarding carousel, Apple Watch app. (Locales beyond English are *out of scope but not out of architecture* — see §12.)

---

## 3. Technology Stack

| Layer | Choice | Rationale |
|---|---|---|
| Language | Dart 3.x — records, patterns, sealed classes | Exhaustive `switch` over session status / block kinds / sync states. |
| UI | Flutter, Material 3, Impeller | Themed far enough that it won't read as stock Material. |
| State | **Riverpod v2 + `riverpod_generator`** (`Notifier` / `AsyncNotifier` / `StreamNotifier`) | The app is a graph of derived state (plan → today → live log → adherence → charts). A set toggle should rebuild one row, not a screen. |
| Local DB | **Drift** (SQLite) — source of truth | Insights are relational time-series aggregation. Typed SQL + reactive `Stream` queries mean charts recompute themselves on write. |
| Remote | **Supabase** — Postgres, Storage, Realtime, anonymous Auth | Durable backup, multi-device path, and a real RLS boundary. Reached only through the sync layer. |
| Sync | Custom outbox + pull-since engine (§6) | No off-the-shelf Flutter↔Supabase offline sync is mature enough to bet ten weeks of logs on. The engine is ~400 lines and fully testable. |
| Navigation | `go_router` — typed, centralized | Deep links from notifications and widgets. |
| Modelling | `freezed` for state/unions; `json_serializable` **data layer only**; pure domain entities | `dart run build_runner build --delete-conflicting-outputs`. |
| Localization | `flutter_localizations` + `gen_l10n` + ARB | §12. |
| Charts | `fl_chart` | Theme-able to tokens; custom painters where needed. |
| Voice | `speech_to_text` (on-device) | Capture only; interpretation is separate. |
| Plan parsing | Heuristic markdown parser + optional Anthropic Messages API | §7. |
| Secrets | `flutter_secure_storage` | API keys, Supabase session. Never in `SharedPreferences`, never in source. |
| Prefs | `shared_preferences` | Theme mode, locale override, last tab. Non-sensitive only. |
| Notifications | `flutter_local_notifications` + `timezone` | Session reminder, check-in due, rest timer. |
| Files | `path_provider`, `share_plus`, `file_picker` | JSON/CSV export & restore. |
| Health (opt) | `health` | Read weight/steps so check-ins don't ask what the phone knows. |
| Observability | `sentry_flutter` (opt-in, PII-scrubbed) | §17. |
| Misc | `intl`, `uuid`, `collection`, `connectivity_plus`, `gap` | |

**Version policy:** pin at scaffold time against current pub releases; don't carry versions from this document.

**Platform config:** iOS `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`, `NSCameraUsageDescription`, `NSPhotoLibraryAddUsageDescription`; Android `RECORD_AUDIO`, `INTERNET`, `POST_NOTIFICATIONS` (API 33+). Every one gets a **permission preamble screen** before the system dialog.

---

## 4. Domain Model

The load-bearing section. **Template** (what was prescribed) is separate from **log** (what happened) — that split is what makes planned-vs-actual and long-range charts possible, and it is brutal to retrofit.

### 4.1 Entity overview

```
Program ──< Phase ──< SessionTemplate ──< BlockTemplate ──< ExerciseTemplate ──> Exercise (catalog)
                                                                                       │
ScheduledSession ──> SessionTemplate                                                   │
        │                                                                              │
        └──< SessionLog ──< SetLog ─────────────────────────────────────────────────────┘

CheckIn ──> Phase (or standalone, date-anchored)
```

### 4.2 Universal row contract (changed in v2)

Every syncable table carries these columns, in both SQLite and Postgres:

| col | type | purpose |
|---|---|---|
| `id` | `uuid` (text in SQLite), **client-generated** | Offline row creation must not wait on a server sequence. v4 is fine; v7 is better (time-ordered → index locality). |
| `owner_id` | `uuid` | The anonymous auth user. RLS predicate. |
| `created_at` | timestamptz | |
| `updated_at` | timestamptz | Conflict resolution + pull cursor. |
| `deleted_at` | timestamptz? | **Soft delete.** Hard deletes cannot propagate to other devices. |
| `sync_state` | enum (SQLite only) | `synced` / `pendingCreate` / `pendingUpdate` / `pendingDelete` / `conflict` |
| `schema_version` | int | Forward-compat guard on payloads. |

### 4.3 Tables

**`exercises`** — the canonical catalog. *The single most important table.* Every set ever logged points here, so "RDL over 10 weeks" survives across programs, phases and renamings.
`id, name_key, custom_name?, aliases (json), pattern (hinge|squat|push|pull|carry|rotation|plyo|conditioning|mobility), load_type (barbell|dumbbellPerHand|kettlebell|machine|cable|bodyweight|band|time|distance), is_unilateral, primary_muscles (json), is_system`

> `name_key` vs `custom_name`: seeded system exercises store a **translation key** (`ex.romanian_deadlift`) so the catalog localizes for free; user-created ones store literal text. See §12.4.

**`programs`** — `id, name, start_date, end_date?, is_active, notes`

**`phases`** — `id, program_id, name, order_index, start_week, end_week, target_session_minutes, rpe_low, rpe_high, check_in_due_at_end`

**`session_templates`** — `id, phase_id, code ("A"), title, day_of_week?, estimated_minutes, order_index`

**`block_templates`** — `id, session_template_id, kind (warmup|main|core|conditioning|cooldown|plyo), title, order_index, target_minutes, notes`

**`exercise_templates`** — the prescription.
`id, block_template_id, exercise_id, order_index, target_sets, target_reps_min, target_reps_max, target_load_kg?, target_load_text?, target_rpe?, rest_seconds, per_side, tempo?, progression_rule (json), notes`

> `progression_rule` encodes "+2.5 kg/week" or "top set + 3 back-off" so the app pre-fills next week's targets instead of asking.

**`scheduled_sessions`** — the materialized calendar.
`id, program_id, session_template_id?, date, week_number, kind (gym|rest|cricket|custom), status (upcoming|inProgress|completed|partial|skipped), planned_duration_min`

> Materialize the whole program on commit (~50 rows for 10 weeks). Makes calendar, adherence and rescheduling trivially queryable.

**`session_logs`** — `id, scheduled_session_id, started_at, ended_at, session_rpe?, energy?, notes?, bodyweight_at_time_kg?`

**`set_logs`** — the atom.
`id, session_log_id, exercise_template_id?, exercise_id, set_index, side (both|left|right), status (done|partial|skipped|substituted), reps?, weight_kg?, duration_sec?, distance_m?, rpe?, is_pr, skip_reason (pain|time|equipment|feltOff|other)?, substituted_for_exercise_id?, note?`

> `exercise_id` is denormalized here deliberately: charts query it without walking the template tree, and history survives template edits or deletions.

**`check_ins`** — `id, program_id, phase_id?, date, weight_kg, waist_cm?, extra (json), photo_refs (json), notes?`

**`metric_definitions`** — user-configurable check-in fields.
`id, key, label_key, unit, input_type (number|scale1to5|yesNo|photo), is_enabled, order_index`

**`prs`** (derived, materialized) — `id, exercise_id, metric (e1RM|maxWeight|maxReps|maxVolume), value, achieved_at, set_log_id`. Recomputed on session finalize.

**`sync_outbox`** (local only, not synced) — `id, table_name, row_id, op, payload (json), attempt_count, last_error?, created_at`

### 4.4 Derived values

- **e1RM** — Epley `w × (1 + reps/30)`, only for `reps ≤ 12` and loadable types. Primary strength trend, because rep ranges shift by design across cycles (4×8 → 5×5 → top-set 3s) and raw weight alone reads as noise.
- **Session tonnage** — `Σ (weight × reps × sideMultiplier)`; dumbbells count both hands.
- **Adherence** — `completedPlannedSets / totalPlannedSets` at session / week / phase. Skipped-with-reason is broken out from silently-missed so a bad week is legible.

---

## 5. Backend Architecture (Supabase)

### 5.1 The no-login problem, stated plainly

"No login" and "remote Postgres" are in tension. A table reachable without an authenticated identity is a table anyone with the anon key — which ships inside your APK and is trivially extractable — can read and write. That's not acceptable even for a personal app.

**Resolution: anonymous auth.** On first launch, call `signInAnonymously()`. Supabase issues a real user row and a real JWT with a stable `auth.uid()`. RLS then works normally, the anon key alone grants nothing, and the session persists in secure storage across launches.

The user-facing experience is unchanged — no screen, no email, no password. But you get:

- A genuine RLS boundary from day one.
- **A free upgrade path:** later, `updateUser()` with an email or `linkIdentity()` with Apple/Google converts the *same* user row into a permanent account. All existing rows keep their `owner_id`. Zero migration, zero data loss. This is exactly why anonymous auth beats a hardcoded device UUID.
- Multi-device becomes a sign-in feature rather than a re-architecture.

**Caveat to design around:** an anonymous identity lives in the app's secure storage. Uninstall the app before linking a real identity and that user is unrecoverable. Mitigations: (a) prompt to link an identity once there's meaningful history — say, after the first phase completes; (b) the local JSON export of §18 is a real escape hatch; (c) surface the anon user id in Settings so it can be noted down.

### 5.2 Schema and RLS

Postgres mirrors §4 one-to-one — same table names, same columns, snake_case throughout (Postgres convention; Drift maps to Dart camelCase).

Every table:

```sql
alter table public.set_logs enable row level security;

create policy "owner_all" on public.set_logs
  for all
  using  (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);

alter table public.set_logs
  alter column owner_id set default auth.uid();
```

Plus, on every table: index on `(owner_id, updated_at)` for the pull cursor, index on `(owner_id, deleted_at)` for live queries, and FKs with `on delete cascade` mirroring the local schema. `set_logs` additionally gets `(owner_id, exercise_id, created_at)` — that's the index every strength chart rides on.

**Never** disable RLS "temporarily to test". That's how personal apps leak.

### 5.3 What lives server-side

| Concern | Where | Why |
|---|---|---|
| Row storage | Postgres | |
| Progress photos | Supabase Storage, **private bucket**, path `{owner_id}/{check_in_id}/{front\|side}.jpg` | Signed URLs only, ~60s TTL. Never a public bucket. |
| Plan parsing via Anthropic | **Edge Function** (`parse-plan`) | Keeps the Anthropic key server-side instead of in an extractable client binary. This is the main reason to have a backend at all beyond storage. |
| Aggregation | **Client-side (Drift)** | Insights must work offline. Do not move aggregation to Postgres views — you'd break principle 3. |
| Migrations | Supabase CLI, versioned SQL in `supabase/migrations/`, committed to the repo | Never click-edit schema in the dashboard; local and remote schemas must move together. |

### 5.4 Environments

Two Supabase projects: `groove-dev` and `groove-prod`, selected by flavor (§16). Never point a debug build at prod data.

---

## 6. Sync Engine

### 6.1 Model

**Local-write-always, background-reconcile.** Writes never await the network.

```
UI ──> Repository ──> Drift (commit) ──> sync_outbox (enqueue) ──> [return: UI is already done]
                                              │
                                    SyncService (background)
                                        ├─ push: drain outbox, batched upserts
                                        └─ pull: rows where updated_at > lastPulledAt
```

### 6.2 Rules

1. **The outbox write is in the same SQLite transaction as the data write.** Otherwise a crash between them silently drops a set.
2. **Push before pull**, so local intent isn't clobbered by a stale server row.
3. **Pull cursor**: one `lastPulledAt` per table in prefs; query `updated_at > cursor` ordered ascending, page 500, advance the cursor to the last row's `updated_at` per page. Use the *server's* timestamp — never the device clock, which can be wrong or moving.
4. **Conflict policy: last-write-wins per row by `updated_at`**, with one exception — `session_logs` and `set_logs` are append-mostly and effectively single-writer, so a conflict there means clock skew or a genuine bug. Log those to Sentry rather than resolving silently.
5. **Soft deletes only.** A pull that returns `deleted_at != null` marks the local row deleted; a purge job hard-deletes locally after 90 days.
6. **Retry with exponential backoff and jitter** (2s → 4s → … → 5min cap), `attempt_count` on the outbox row. After 10 failures, mark `conflict` and surface it in Settings rather than looping forever.
7. **Triggers:** app resume, connectivity regained, session finalize, check-in submit, and a 15-minute periodic tick while foregrounded. **Not** on every set write — batching a 40-set session into one push at finalize is both cheaper and kinder to a gym's dead Wi-Fi.
8. **Realtime is optional and off in v1.** With a single device it's pure cost. Turn it on the day a second device exists.

### 6.3 Sync surfacing

A single unobtrusive status in Settings and a hairline indicator on the Today app bar: `Synced 4m ago` / `3 pending` / `Offline` / `Needs attention`. **Never** a blocking spinner, never a modal error mid-session. Sync failure is not the user's emergency.

---

## 7. Plan Ingestion (Voice / Text / Paste)

Three entry points, one pipeline, one review gate.

```
[ Paste markdown ]                          ┌──────────────────┐
[ Dictate (speech_to_text) ] ──> raw text ──>│ ParsePlanService │──> ParsedPlan (JSON)
[ Type in-app ]                             └──────────────────┘        │
                                                                        ▼
                                                   ┌────────────────────────────────┐
                                                   │ Review & Fix (editable)        │
                                                   │ confidence flags, exercise      │
                                                   │ matching, unresolved items      │
                                                   └────────────────────────────────┘
                                                                        │ commit
                                                                        ▼
                                                     Program + Phases + Templates + Schedule
```

### 7.1 Two parsers behind one interface

- **`HeuristicPlanParser`** (default) — regex over markdown tables (`| # | Exercise | Sets × Reps | Rest | Notes |`), headings for phases and days, `N × M` set-rep patterns. Deterministic, offline, free, and it handles the exact format your plans arrive in. **Build this one first.**
- **`LlmPlanParser`** — calls the `parse-plan` Edge Function (§5.3), which holds the Anthropic key and enforces the JSON schema. System prompt: *"Return ONLY valid JSON matching this schema. No prose, no fences."* Strip stray fences defensively before decode; on failure retry once with the error appended, then fall back to heuristic.

### 7.2 Target schema (abridged)

```json
{
  "program": { "name": "string", "startDate": "YYYY-MM-DD", "weeks": 10 },
  "phases": [{
    "name": "Cycle 1 — Foundation",
    "startWeek": 2, "endWeek": 4,
    "targetSessionMinutes": 90, "rpeLow": 6.0, "rpeHigh": 7.5,
    "sessions": [{
      "code": "A", "title": "Push + Core", "dayOfWeek": 7,
      "blocks": [{
        "kind": "main", "targetMinutes": 55,
        "exercises": [{
          "name": "Landmine press (single-arm)",
          "sets": 4, "repsMin": 8, "repsMax": 8, "perSide": true,
          "restSeconds": 90,
          "progression": { "type": "linearWeekly", "incrementKg": 2.5 },
          "confidence": 0.93
        }]
      }]
    }]
  }],
  "unresolved": ["'Rotary torso machine' — no catalog match"]
}
```

### 7.3 Exercise resolution

Exact match → alias match → normalized (lowercase, strip parentheticals and equipment words) → trigram similarity ≥ 0.75. Below threshold, the review screen shows a chip: **[ Rotary torso machine ]** → *Match to existing* / *Create new*. Confirming a match writes an alias, so the catalog gets smarter with every import.

### 7.4 Voice, specifically

Voice is **capture, not command**:

1. **Plan dictation** — long-form, one shot, into the parser. Live waveform + interim transcript, editable before parsing.
2. **In-session quick log** — mic FAB: *"sixty kilos, eight reps, RPE seven"*. Parsed by a **small local grammar** (numbers + unit keywords + rpe), never over the network. Pre-fills the active set for one-tap confirmation; low confidence opens the stepper with what it heard rather than guessing silently.

**Never** put a network round-trip between "user speaks" and "set is recorded."

---

## 8. Scheduling & Cycles

### 8.1 Program setup

One sheet after parsing: **start date**, **cadence type**, **training days**.

- **Weekly** — repeating day-of-week pattern (your case: Sun–Thu gym, Fri rest, Sat cricket).
- **Monthly** — day-of-month or Nth-weekday recurrence.
- **Custom cycle** — "N days on / M days off" rotation, or a hand-drawn mini-calendar pattern.

Days are picked on a **7-chip week strip**: tap a chip, pick Day A–E from a bottom sheet. Zero typing.

### 8.2 Materialization & drift

- **Missed a day** stays `skipped` and does **not** cascade-shift. Adherence tells the truth.
- **Cricket overrides gym** (your Rule 5) is a first-class action: *Convert to cricket day*, reason stored, so a light week reads as intentional.
- **Reschedule** by long-press → drag within the week. Cross-week moves warn about phase boundaries.
- **Plan edits apply forward only.** Editing a template affects future scheduled sessions; completed logs are immutable. Absolute rule — history must not lie.

### 8.3 Phase transitions

Completing the last session of a phase (or passing its end date) raises **PhaseCompleted** → check-in prompt (§10) → phase report → "Start Cycle N" confirmation, which applies the new targets and progression rules.

---

## 9. The Logging Loop (tap-first, type-last)

### 9.1 Today

Above the fold: today's session card — day code, title, block summary, estimated minutes, thin weekly adherence ring. Below: the 7-day strip and a "last session" recap with one delta stat. Rest day gets a deliberately calm empty state; cricket day offers a lightweight match log instead of nothing.

### 9.2 Active session — the core screen

Blocks stack vertically; the active exercise expands, others collapse to one line with a completion pill (`3/4`).

```
Landmine press (single-arm) · 4 × 8 · rest 90s        prev: 25 kg × 8 @7
┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐
│ 25×8 │ │ 25×8 │ │ 27×8 │ │  4   │        [ ✓ all as planned ]
└──────┘ └──────┘ └──────┘ └──────┘
   ✓        ✓        ✓      active
```

- **Tap a chip** → logs it with prefilled values (last session's load, or the progression rule's suggestion). One tap = one set. The 90% path.
- **Long-press / drag up** → inline editor: weight ± stepper (2.5 kg default, 1 kg dumbbells, per-load-type configurable), reps ± stepper, RPE as a 6-dot row. No keyboard; a keypad affordance exists for outliers.
- **Swipe left** → skip with a 4-chip reason sheet (*pain · time · equipment · felt off*). Reason capture is what makes Insights honest.
- **Swipe right on an exercise** → substitute from catalog; block stays intact, set flagged `substituted`.
- **"✓ all as planned"** → completes the exercise at target values. This is why a good session can be ~10 taps.
- Final set **auto-starts the rest timer** — slim progress bar under the app bar, local notification + haptic if backgrounded.

### 9.3 Finalize

One sheet: session RPE (6 dots), energy (5 faces), optional note (voice or text, both optional). Then a summary — sets completed, tonnage, duration, PRs detected — and a single sync push.

### 9.4 Interruption safety

The active session persists to Drift **on every set write**, not on finish. `activeSessionId` in prefs restores mid-session on cold start. Store `restStartedAt` as a **timestamp**, never a running counter — the OS will suspend you mid-rest.

---

## 10. Check-ins & Reassessment

### 10.1 Triggers

- **Phase end** (your Week 1 / 4 / 7 / 10 gates) — prompted on next launch, dismissible once, re-raised next day.
- **Weekly** — optional light Friday weight prompt, off by default.
- **Manual** — always available from Insights.

### 10.2 Form

Driven by `metric_definitions`, so it stays two or three fields long:

1. **Weight** — horizontal ruler picker, snaps to 0.1 kg with a haptic tick per notch, seeded from last value or Health/Health Connect.
2. **Waist** — same widget, optional.
3. **1–2 configurable extras** — default `Sleep quality` and `Joint pain check` as 5-point scales.
4. **Progress photos** — optional front/side, stored locally, uploaded to the private bucket only if photo sync is enabled (§18).

Plus the plan's qualitative gates as yes/no chips: *shoulder pain-free? knee stable? back pain-free during hinges?* A "no" raises a warning card and tags the phase so trend charts can show it.

### 10.3 Phase report

Weight delta, adherence %, tonnage change, top-5 lifts' e1RM change, and a plain-language line ("87% of planned sets; RDL e1RM up 14%"). Exportable as text to paste back to a coach.

---

## 11. Insights & Analytics

### 11.1 Global filter

A persistent segmented control: **Day · Week · Month · Cycle · All**. Single Riverpod provider; every chart watches it. Range navigation by horizontal swipe on the chart itself.

### 11.2 Cards, in priority order

| # | Card | Chart | Why |
|---|---|---|---|
| 1 | **Adherence** | Ring + 7/30-bar strip | The number the app exists to produce. Skipped-for-pain in its own colour. |
| 2 | **Body weight** | Line + 7-day moving average | Your 84.5 → 78 kg arc. Trend line heavy, raw dots faint — daily weight swings ±1.5 kg on water alone. Phase boundaries as vertical rules. |
| 3 | **Strength progression** | Multi-line e1RM + exercise picker | Defaults to RDL, hip thrust, DB press, lat pulldown, hack squat. |
| 4 | **Volume load** | Weekly bars stacked by pattern | Catches the quiet drift away from posterior chain work. |
| 5 | **Consistency** | Heatmap | Streaks, sessions/week; cricket days shaded distinctly. |
| 6 | **Session load** | RPE × duration scatter | Fatigue proxy — rising RPE at flat tonnage means under-recovered. |
| 7 | **Records** | List | Every PR with the set that made it. |

### 11.3 Query strategy

All aggregation in **SQL views / Drift queries**, exposed as `Stream`s wrapped in `.autoDispose` `AsyncNotifier`s. Never aggregate full history in Dart on the UI thread. Precompute into `weekly_summaries` on finalize once history grows past a year.

### 11.4 Chart quality bar

Draw-in animation on first appearance only (~450ms `easeOutCubic`), not on every rebuild. Touch shows a snapped tooltip with a light haptic. Pre-data empty state: faint dashed axis + "3 more sessions until this chart means something."

---

## 12. Localization & Internationalization

English only at launch. The point is that **adding Bengali or Arabic later is a translation job, not a refactor.**

### 12.1 Architecture

`flutter_localizations` + **`gen_l10n`** with ARB files — first-party, compile-checked, no runtime key lookups that fail silently.

```yaml
# l10n.yaml
arb-dir: lib/l10n/arb
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart
output-class: L10n
nullable-getter: false
synthetic-package: false
output-dir: lib/l10n/generated
```

```dart
MaterialApp.router(
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,   // [en] today
  locale: ref.watch(localeProvider),          // null = follow system
)
```

`localeProvider` reads a persisted override from prefs; `null` means follow the system. The Settings language row exists from v1 and simply shows one option — so the plumbing is proven, not theoretical.

### 12.2 Non-negotiable rules

1. **No hardcoded user-facing string, ever.** Enforce with `flutter_lints` plus a custom CI grep for string literals inside `Text(` / `label:` / `title:`. It's much cheaper to enforce from commit one than to sweep 8,000 lines later.
2. **ICU plurals and selects in ARB, not Dart `if`s.** `"{count, plural, =0{No sets} =1{1 set} other{{count} sets}}"`. Languages with 4+ plural forms will break any hand-rolled ternary.
3. **Never concatenate.** `"$sets sets in $minutes min"` is untranslatable — word order differs by language. Use one placeholder-bearing message.
4. **Every ARB entry gets a `@description`** and, where ambiguous, an `@@context`. "Set" is a noun, a verb and a workout unit; a translator can't guess.
5. **Format numbers, dates and durations through `intl`** with the active locale — `NumberFormat`, `DateFormat`. Bengali and Arabic use different digit glyphs; a hardcoded `toStringAsFixed(1)` will look wrong. Weight input parsing must accept locale decimal separators (`78,4` in much of Europe).
6. **RTL-ready from day one** — `EdgeInsetsDirectional`, `AlignmentDirectional`, `start`/`end` over `left`/`right`, `TextDirection`-aware custom painters. Verify with `MaterialApp(locale: Locale('ar'))` in a debug toggle even before Arabic ships. **Charts are the usual RTL casualty** — axis order and tooltip anchoring both need checking.
7. **Layout must survive ~40% string growth.** German and Bengali run long. No fixed-width buttons around text; test with a pseudo-locale (`en_XA`) that doubles and accents every string.
8. **First day of week is locale data, not a constant.** Your week starts Sunday; that's `MaterialLocalizations.firstDayOfWeekIndex`, not a hardcoded 7.

### 12.3 Key naming

`screen_element_variant` — `today_sessionCard_startButton`, `insights_filter_weekly`, `checkIn_weight_label`. Flat namespace, alphabetized, no nesting (ARB is flat anyway).

### 12.4 Localizing database content

The hard part, and the reason for `name_key` in §4.3. Three content classes:

| Class | Strategy |
|---|---|
| **System exercises, block kinds, skip reasons, metric labels** | Store a **key** (`ex.romanian_deadlift`), resolve through ARB at render. Ships localized automatically. |
| **User-created exercises, program names, notes** | Store literal text, never translated. Correct — it's the user's own language. |
| **Parsed plan content** | Literal, in whatever language the plan arrived. The parser tags `source_locale` for future reference. |

A single `exerciseDisplayName(Exercise, L10n)` helper resolves key-or-literal in one place, so no widget ever has to know which class it's holding.

### 12.5 Roadmap locales

Bengali (`bn`), Hindi (`hi`), Arabic (`ar` — RTL validation), Spanish (`es`). Ship whichever, whenever; the architecture doesn't care.

---

## 13. UI Design System

### 13.1 Direction

**Dark-first, editorial, high-contrast, near-monochrome with one accent.** Not neon-gym, not pastel-wellness. Reads as an instrument, not a coach. Light mode exists; dark is the default (gym lighting, evening sessions).

### 13.2 Colour tokens

| Token | Dark | Light | Use |
|---|---|---|---|
| `background` | `#0B0C0E` | `#FAFAF7` | Page |
| `surface` | `#16181C` | `#FFFFFF` | Cards |
| `surfaceRaised` | `#1E2126` | `#F2F2EE` | Sheets, active rows |
| `outline` | `#2A2E35` | `#E2E2DC` | Hairlines, chip borders |
| `textPrimary` | `#F5F6F7` | `#101114` | |
| `textSecondary` | `#9BA1AB` | `#5F6570` | |
| `accent` | `#D6FF3E` | `#4B6B00` | Primary action, completed sets, active series |
| `accentMuted` | `#3A4416` | `#E7F5B0` | Fills, rings |
| `success` | `#4ADE80` | `#15803D` | PRs |
| `warning` | `#FBBF24` | `#B45309` | Behind / missed |
| `danger` | `#F87171` | `#B91C1C` | Pain flags |

Separate dark surfaces by **tone**, never by black drop-shadow. Shadows ≤12% opacity, large blur, no visible offset. Verify contrast ≥4.5:1 for body text in both modes — `accent` on `background` passes; `accent` as *text* on `surfaceRaised` needs checking.

### 13.3 Typography

Body/UI: **Inter** (or system). Numerals everywhere: **`FontFeature.tabularFigures()`** — non-negotiable in a tracker; proportional digits make weight columns wobble as they update.

| Style | Size / weight | Use |
|---|---|---|
| `display` | 40 / w600, −1.5 tracking | Big stats ("78.4 kg") |
| `titleLarge` | 24 / w600 | Screen titles |
| `titleMedium` | 18 / w600 | Card headers, exercise names |
| `body` | 15 / w400, height 1.45 | |
| `label` | 13 / w500, +0.2 tracking | Chips, tabs |
| `mono` | 13 / w500 tabular | Set chips, tables |

All sizes scale with the user's text-size setting (clamped `textScaler` 0.85–1.4 — beyond that, set chips break).

### 13.4 Spacing, radius, elevation

4pt scale (`4/8/12/16/24/32/48`) in a `Spacing` token class. Page gutter `20`. Radii `8` chips, `16` cards, `28` sheets/FAB. One shared `AppShadow.soft`.

### 13.5 Navigation

`ShellRoute` + 4-tab bottom bar: **Today · Plan · Insights · Profile**. Modal `fullscreenDialog` routes for active session, plan import review, and check-in.

### 13.6 Required states

Every list and chart ships three designed states: **empty** (icon + one honest line + one action), **loading** (skeleton shaped like the real content — never a lone centred spinner), **error** (what happened + retry). Checklist, not aspiration.

---

## 14. Motion & Haptics

### 14.1 Tokens

| Token | ms | Curve | Use |
|---|---|---|---|
| `micro` | 120 | `easeOut` | Chip press, colour change |
| `base` | 220 | `easeOutCubic` | Expand/collapse, cross-fade, reorder |
| `emphasis` | 380 | `easeOutBack` | Set-complete check, PR badge |
| `page` | 300 | `easeOutCubic` | Route transitions |
| `chart` | 450 | `easeOutCubic` | Series draw-in (once per appearance) |

### 14.2 Signature moments

- **Set chip completion** — scale 1.0 → 0.94 → 1.06 → 1.0, fill sweeps from the leading edge, checkmark strokes on via `CustomPainter` path animation. The most-repeated interaction in the app; it gets the most craft.
- **Session card → active session** — `Hero`, with block rows staggered in at 40ms intervals.
- **Rest timer** — hairline bar shifting `accent` → `warning` in the last 10s, final second pulses.
- **Adherence ring** — `TweenAnimationBuilder` sweep from 0 on every value change.
- **Phase completion** — one restrained full-screen moment (ring closes, number counts up). Once per three weeks; it can afford to be nice.
- **Weight ruler** — physics scroll with notch snapping.

### 14.3 Haptics

Only alongside a visual change, never alone, never in a loop:

| Event | Feedback |
|---|---|
| Set chip logged | `selectionClick()` |
| Stepper increment | `selectionClick()` (throttled ≥60ms) |
| Ruler notch | `selectionClick()` |
| Exercise completed | `lightImpact()` |
| Session finalized | `mediumImpact()` |
| New PR | `heavyImpact()` |
| Rest timer done | `mediumImpact()` + notification |
| Blocked action | short `vibrate()` |

Global toggle in Settings; honour `MediaQuery.disableAnimations` by dropping to cross-fades.

### 14.4 Performance guardrails

Set chips `const` where possible, rebuilt via `ref.watch(...select(...))` on a single set's state. `RepaintBoundary` around charts and the rest timer. Every `AnimationController`, `PageController`, `TextEditingController`, `FocusNode`, `Timer` and `StreamSubscription` disposed — a leak is a bug, not a nicety.

---

## 15. Project Structure

```
lib/
├── main_dev.dart / main_stg.dart / main_prod.dart   # flavor entrypoints
├── bootstrap.dart                                    # shared init + runZonedGuarded
├── app/
│   ├── app.dart                  # MaterialApp.router, theme + l10n wiring
│   ├── router.dart               # go_router typed routes
│   └── env.dart                  # AppEnv: supabaseUrl, anonKey, flavor
├── l10n/
│   ├── arb/app_en.arb
│   └── generated/                # gitignored, built by gen_l10n
├── core/
│   ├── design/
│   │   ├── tokens.dart           # colors, spacing, radii, durations
│   │   ├── theme.dart
│   │   └── widgets/              # AppCard, SetChip, StepperField, RulerPicker,
│   │                             # RpeDots, AdherenceRing, EmptyState,
│   │                             # ErrorState, Skeleton, SyncBadge
│   ├── haptics.dart
│   ├── formatters.dart           # locale-aware number/date/duration
│   ├── result.dart
│   └── extensions/
├── data/
│   ├── db/
│   │   ├── database.dart         # @DriftDatabase
│   │   ├── tables/
│   │   ├── daos/                 # PlanDao, LogDao, InsightsDao, CheckInDao, OutboxDao
│   │   └── migrations/
│   ├── remote/
│   │   ├── supabase_client.dart
│   │   ├── auth_service.dart     # anonymous sign-in, identity linking
│   │   └── endpoints/            # per-table remote data sources
│   ├── sync/
│   │   ├── sync_service.dart
│   │   ├── outbox.dart
│   │   ├── pull_cursor.dart
│   │   └── conflict_resolver.dart
│   ├── dto/                      # json_serializable lives ONLY here
│   ├── mappers/                  # DTO <-> domain entity
│   └── repositories/             # *RepositoryImpl
├── domain/
│   ├── entities/                 # pure
│   ├── repositories/             # abstract interfaces
│   └── services/
│       ├── progression_service.dart
│       ├── metrics_service.dart  # e1RM, tonnage, adherence
│       ├── pr_service.dart
│       └── plan_parser/
└── features/
    ├── today/            {view, widgets, controller}
    ├── active_session/
    ├── plan/{calendar, editor, import}
    ├── insights/
    ├── check_in/
    ├── records/
    └── settings/

supabase/
├── migrations/           # versioned SQL, committed
├── functions/parse-plan/
└── seed.sql              # exercise catalog
```

**Layering rule:** `features/*` may import `domain` and `core`, never `data`. Repository interfaces live in `domain`; implementations are injected via Riverpod overrides in `bootstrap.dart` — so every controller is unit-testable against a fake repo, and Supabase never leaks into a widget.

---

## 16. Release Engineering & Flavors

| Flavor | App ID | Display name | Supabase | Sentry |
|---|---|---|---|---|
| `dev` | `lab.aether.groove.dev` | Groove Dev | `groove-dev` | off |
| `stg` | `lab.aether.groove.stg` | Groove Stg | `groove-dev` | on |
| `prod` | `lab.aether.groove` | Groove | `groove-prod` | on |

- Three flavors installable side by side — you can keep a real logging history on prod while breaking dev.
- Config via `--dart-define-from-file=env/dev.json`, read into `AppEnv`. **No secrets in `env/*.json`** beyond the Supabase URL + anon key (both public by design and protected by RLS). The Anthropic key never leaves the Edge Function.
- Android: `flavorDimensions "env"`, `applicationIdSuffix`, per-flavor `resValue` app label and icon (tint dev/stg icons so you can tell them apart on the home screen).
- iOS: three schemes + xcconfigs; `PRODUCT_BUNDLE_IDENTIFIER` and `CFBundleDisplayName` per configuration.
- Release builds: `--obfuscate --split-debug-info=build/symbols` (upload symbols to Sentry), R8 on Android, `--split-per-abi` or App Bundle.
- Versioning: semver `major.minor.patch+build`, build number from CI run number.
- Icon/splash: `flutter_launcher_icons` + `flutter_native_splash`, generated per flavor.

---

## 17. Observability, Testing & Quality Gates

### 17.1 Observability

- `runZonedGuarded` + `FlutterError.onError` + `PlatformDispatcher.instance.onError` → Sentry, **opt-in**, with `beforeSend` scrubbing notes, exercise names and photo paths. A crash report should tell you *where*, not *what you lifted*.
- Structured local logging with levels; a Settings screen dumps the last 500 lines for debugging a real gym failure after the fact.
- Sync health counters (pending ops, last success, failure streak) exposed in Settings — the one place a silent backend failure would otherwise hide for weeks.

### 17.2 Testing

| Layer | Tool | Must cover |
|---|---|---|
| Unit | `test` | `metrics_service` (e1RM edge cases: 0 reps, bodyweight, unilateral doubling), `progression_service`, both plan parsers against real plan fixtures |
| DB | `drift` in-memory | **Every migration, step by step, with seeded data.** A bad migration is the one bug that destroys history. |
| Sync | fakes | Outbox drains, retries, dedupes; conflict resolution; offline→online transition; crash between data write and outbox write |
| Widget | `flutter_test` + `ProviderScope` overrides | Set chip states, empty/loading/error for every list, RTL and 1.4× text-scale golden tests |
| Golden | `golden_toolkit` | Today, Active Session, Insights in light/dark |
| Integration | `integration_test` | The full loop: create program → log a session → finalize → chart updates |

CI (GitHub Actions): `flutter analyze` → `dart format --set-exit-if-changed` → tests with coverage → l10n hardcoded-string grep → build all three flavors on PR.

### 17.3 Definition of done for a feature

Analyzer clean, tests written, empty/loading/error states designed, dark + light verified, RTL and 1.4× text scale don't overflow, every controller disposed, no hardcoded user-facing string, and it works with the network off.

---

## 18. Privacy, Security & Data Safety

- **RLS on every table, no exceptions.** The anon key is public by design; RLS is the only real boundary.
- **Photos** default to **local-only**, in the app's private documents directory, referenced by *relative* path (iOS container paths change between builds — never persist absolute paths). Cloud photo sync is an explicit opt-in toggle; when on, private bucket + short-lived signed URLs only.
- **No analytics, no ad SDKs, no third-party trackers.** Sentry is opt-in and scrubbed.
- **Local JSON export remains a first-class feature**, not a fallback: full relational dump with `schemaVersion`, shared via `share_plus`, restorable with a preview-diff. Plus a **silent weekly auto-export** keeping the last 4. Supabase is not a backup strategy on its own — a bad migration or an RLS mistake propagates to the server too.
- **Migrations** with explicit `MigrationStrategy` and a test per version step. `deleteOnSchemaChange` never leaves dev.
- **Supabase session** in `flutter_secure_storage`; auto-refresh on resume; a failed refresh must degrade to offline mode, never to a data-loss path or a login wall.
- **Permission preambles** for mic, speech, photos, health — each with a graceful denied path, because every voice feature has a tap equivalent.
- If the app is ever published: the anonymous-auth identity plus health-adjacent data means a privacy policy URL, an App Store privacy label (Health & Fitness, Identifiers, Photos), and a working account-deletion path — Apple requires deletion, not just sign-out.

---

## 19. Roadmap

### Phase 1 — Foundation (local, no backend yet)

1. Flavors, app identity, theme tokens, l10n scaffold, CI. **First commit, not later** — this is the "production-grade" bill and it's cheapest now.
2. Drift schema with UUID keys + sync columns + seeded catalog (~120 exercises covering your plan).
3. Manual program builder (phases → sessions → blocks → exercises). **Before the parser** — the parser writes into this model, so it must exist and be right first.
4. Week-strip day assignment + schedule materialization.
5. **Active session screen**: set chips, steppers, RPE dots, rest timer, crash-safe persistence.
6. Today + finalize + summary.
7. Local JSON export/import.

**Done when:** you log a full 90-minute session without opening the keyboard once, with the network off.

### Phase 2 — Backend

8. Supabase project, schema migrations, RLS policies, anonymous auth.
9. Sync engine: outbox, push, pull cursor, backoff, conflict logging.
10. Sync status surfacing + Settings diagnostics.
11. Storage bucket + opt-in photo sync.

### Phase 3 — Ingestion & insight

12. Heuristic markdown parser → review screen → commit.
13. `parse-plan` Edge Function + LLM parser behind the same interface.
14. Voice dictation for plan capture.
15. Insights tab with the Day/Week/Month/Cycle filter.
16. Check-ins, metric definitions, phase report.

### Phase 4 — Leverage

17. PR detection + Records + celebration moment.
18. Progression rules auto-prefilling next week's targets.
19. In-session voice quick-log (local grammar).
20. Notifications: session reminder, check-in due, rest timer.
21. Health / Health Connect read for weight + steps.
22. Home-screen widget: today's session, one-tap start.

### Phase 5 — If it earns it

Identity linking (email/Apple) + true multi-device with Realtime, Apple Watch companion, plate calculator, supersets/complexes as a first-class block kind, cricket match log correlated against training load, additional locales.

---

## 20. Suggestions & Open Decisions

### 20.1 Suggestions worth taking

1. **Anonymous auth, not a hardcoded device ID.** Same zero-friction UX, but you get RLS and a free upgrade to a real account later with no data migration. This is the single highest-leverage decision in v2.
2. **Build the manual builder before the parser.** The parser's output *is* the manual model. Wrong model = wrong data, faster.
3. **Model planned-vs-actual from day one.** Retrofitting the template/log split later is a migration nightmare, and it's the only thing separating this from a generic logger.
4. **Client-generated UUIDs, from the very first table.** Int autoincrement plus offline creation plus sync equals guaranteed collisions. Changing PK types after you have real data is the worst refactor on this list.
5. **Soft deletes everywhere.** Hard deletes can't propagate; a second device would silently resurrect them.
6. **Do the l10n scaffold in week one even though English is the only locale.** The cost is a day now versus a week of string archaeology later. The `name_key` decision in the exercise catalog (§12.4) is the part people forget and pay for.
7. **Reason-coded skips.** A skip with a reason is data; a silent gap is guilt. Your plan has explicit injury gates — the app should be able to answer "did the plyo block coincide with knee complaints?"
8. **Substitution as a real concept, not a note.** Racks get busy. Logging the substitute against the catalog keeps charts honest instead of showing a gap.
9. **Trend line over raw weight.** ±1.5 kg daily water swing will otherwise make you feel bad every Tuesday.
10. **Annotate phase boundaries on every time chart.** "Weight stalled in Cycle 2" beats a squiggle.
11. **Push sync at finalize, not per set.** Batching 40 sets into one push is cheaper and survives gym Wi-Fi.
12. **Don't gamify.** Streaks fine; badges, levels and confetti storms age badly in an app only you open. One restrained PR moment is enough.

### 20.2 Decisions made for you

| Decision | Rejected | Why |
|---|---|---|
| Drift local + Supabase remote, local as truth | Supabase as the live datastore | A dropped connection mid-set is unacceptable. |
| Anonymous auth | Public tables / device UUID | Real RLS boundary + free account upgrade path. |
| Custom sync engine | PowerSync / Realtime-as-sync | Purpose-built beats a heavy dependency for ~10 tables; PowerSync is worth revisiting only if multi-device gets serious. |
| Client UUIDs, soft deletes | Server sequences, hard deletes | Offline creation and delete propagation. |
| Aggregation client-side | Postgres views | Insights must work offline. |
| Edge Function for LLM parsing | Client-side API key | An API key in a shipped binary is an extracted API key. |
| `gen_l10n` + ARB | `easy_localization`, `slang` | First-party, compile-checked, no runtime key failures. |
| `lab.aether.groove` | `aether.lab.groove` | Correct reverse-DNS. |
| e1RM as primary strength metric | Raw top weight | Rep ranges shift by design across cycles. |
| Dark-first, single accent | Multi-colour fitness palette | Reads as an instrument; ages better. |

### 20.3 Still open

1. **Units** — kg only, or dual kg/lb? (Assumed kg-only; removes a class of conversion bugs. Note this interacts with locale — a future `en_US` user would expect lb.)
2. **Per-side logging** — separate left/right rows for unilateral work, or one row for both? Separate is more honest, ~2× the taps. (Assumed one row, with an optional per-exercise toggle.)
3. **Warm-up blocks** — individual sets, or one "done" checkbox per block? (Assumed a single checkbox; logging band pull-aparts individually is friction with no analytical payoff.)
4. **Conditioning detail** — is bike-interval detail (rounds, resistance, incline) worth capturing, or is "did it: yes" enough?
5. **Cricket day** — a real match-log entity in v1, or just a marker? Gym-volume vs Saturday-performance is the most interesting chart in the app, but only if you'd actually fill it in.
6. **Identity linking prompt timing** — after the first completed phase, or never until you ask? (Assumed: a single dismissible prompt at first phase completion.)

---

*End of ADR — Groove v2.0*
