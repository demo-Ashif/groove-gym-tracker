import 'package:drift/drift.dart';

import '../../../domain/enums/training_enums.dart';
import 'catalog_tables.dart';
import 'sync_columns.dart';

/// The **template** side of the model (ADR §4): what was prescribed, kept
/// strictly separate from what happened. That split is what makes
/// planned-vs-actual and long-range charts possible, and it is brutal to
/// retrofit.
///
/// Template edits apply **forward only** — completed logs are immutable
/// (ADR §8.2). History must not lie.

@TableIndex(name: 'idx_programs_owner_updated', columns: {#ownerId, #updatedAt})
@TableIndex(name: 'idx_programs_owner_deleted', columns: {#ownerId, #deletedAt})
@DataClassName('ProgramRow')
class Programs extends Table with SyncedRow {
  TextColumn get name => text()();

  /// Date-only, stored as `YYYY-MM-DD` text rather than a timestamp. A
  /// program starts on a *day*, and putting a clock on it means a user in a
  /// negative UTC offset sees the wrong start date.
  TextColumn get startDate => text().withLength(min: 10, max: 10)();

  TextColumn get endDate => text().withLength(min: 10, max: 10).nullable()();

  BoolColumn get isActive => boolean().withDefault(const Constant(false))();

  TextColumn get notes => text().nullable()();

  /// JSON. How the program repeats (ADR §8.1) — kept so a re-commit after a
  /// plan edit can regenerate the calendar without asking the user to redraw
  /// the week strip. Null until the schedule is first committed.
  TextColumn get schedulePattern => text().nullable()();
}

@TableIndex(name: 'idx_phases_program', columns: {#programId, #orderIndex})
@DataClassName('PhaseRow')
class Phases extends Table with SyncedRow {
  TextColumn get programId =>
      text().references(Programs, #id, onDelete: KeyAction.cascade)();

  TextColumn get name => text()();

  IntColumn get orderIndex => integer()();

  /// Inclusive 1-based program week range.
  IntColumn get startWeek => integer()();
  IntColumn get endWeek => integer()();

  IntColumn get targetSessionMinutes => integer().nullable()();

  RealColumn get rpeLow => real().nullable()();
  RealColumn get rpeHigh => real().nullable()();

  /// Whether finishing this phase raises a check-in prompt (ADR §10.1).
  BoolColumn get checkInDueAtEnd =>
      boolean().withDefault(const Constant(true))();
}

@TableIndex(
  name: 'idx_session_templates_phase',
  columns: {#phaseId, #orderIndex},
)
@DataClassName('SessionTemplateRow')
class SessionTemplates extends Table with SyncedRow {
  TextColumn get phaseId =>
      text().references(Phases, #id, onDelete: KeyAction.cascade)();

  /// The day letter the plan uses — "A", "B". Short, user-authored, not
  /// translated.
  TextColumn get code => text()();

  TextColumn get title => text()();

  /// ISO-8601 weekday, 1 = Monday … 7 = Sunday. Null when the template isn't
  /// pinned to a weekday. The *display* order of a week still comes from
  /// `MaterialLocalizations.firstDayOfWeekIndex`, never from this
  /// (ADR §12.2 rule 8).
  IntColumn get dayOfWeek => integer().nullable()();

  IntColumn get estimatedMinutes => integer().nullable()();

  IntColumn get orderIndex => integer()();
}

@TableIndex(
  name: 'idx_block_templates_session',
  columns: {#sessionTemplateId, #orderIndex},
)
@DataClassName('BlockTemplateRow')
class BlockTemplates extends Table with SyncedRow {
  TextColumn get sessionTemplateId =>
      text().references(SessionTemplates, #id, onDelete: KeyAction.cascade)();

  TextColumn get kind => textEnum<BlockKind>()();

  TextColumn get title => text()();

  IntColumn get orderIndex => integer()();

  IntColumn get targetMinutes => integer().nullable()();

  TextColumn get notes => text().nullable()();
}

/// The prescription itself — one row per exercise slot in a block.
@TableIndex(
  name: 'idx_exercise_templates_block',
  columns: {#blockTemplateId, #orderIndex},
)
@TableIndex(name: 'idx_exercise_templates_exercise', columns: {#exerciseId})
@DataClassName('ExerciseTemplateRow')
class ExerciseTemplates extends Table with SyncedRow {
  TextColumn get blockTemplateId =>
      text().references(BlockTemplates, #id, onDelete: KeyAction.cascade)();

  /// Restricted, not cascaded: deleting a catalog entry that a plan still
  /// prescribes would silently empty a session. Catalog rows are soft-deleted
  /// instead.
  TextColumn get exerciseId =>
      text().references(Exercises, #id, onDelete: KeyAction.restrict)();

  IntColumn get orderIndex => integer()();

  IntColumn get targetSets => integer()();

  /// A single prescribed rep count. Mutually exclusive with
  /// [targetDurationSec] — a slot is measured by reps or by the clock, never
  /// both. Enforced in the repository rather than by a CHECK, because a slot
  /// mid-edit may legitimately have neither.
  IntColumn get targetReps => integer().nullable()();

  /// Prescribed working time in seconds, for exercises the clock measures:
  /// stationary bike, treadmill, cross trainer, plank.
  IntColumn get targetDurationSec => integer().nullable()();

  /// Planned working load. Optional, but recording it is what lets Insights
  /// chart planned workload against what was actually lifted.
  RealColumn get targetLoadKg => real().nullable()();

  /// For prescriptions that aren't a number — "bodyweight", "light band".
  /// Literal text in the plan's own language.
  TextColumn get targetLoadText => text().nullable()();

  RealColumn get targetRpe => real().nullable()();

  IntColumn get restSeconds => integer().withDefault(const Constant(90))();

  /// Reps are per side rather than total.
  BoolColumn get perSide => boolean().withDefault(const Constant(false))();

  /// Tempo notation such as `3-1-1-0`. Symbols only; no translation needed.
  TextColumn get tempo => text().nullable()();

  /// JSON. Encodes "+2.5 kg/week" or "top set + 3 back-off" so the app
  /// pre-fills next week's targets instead of asking (ADR §4.3).
  TextColumn get progressionRule => text().nullable()();

  TextColumn get notes => text().nullable()();
}

/// The materialized calendar. The whole program is written on commit — about
/// 50 rows for ten weeks — which makes the calendar, adherence and
/// rescheduling trivially queryable (ADR §4.3).
@TableIndex(name: 'idx_scheduled_sessions_date', columns: {#date})
@TableIndex(
  name: 'idx_scheduled_sessions_program_week',
  columns: {#programId, #weekNumber},
)
@DataClassName('ScheduledSessionRow')
class ScheduledSessions extends Table with SyncedRow {
  /// Null for a day that belongs to no program — a session logged after the
  /// fact for training that happened before the app existed (ADR §8.2
  /// backfill). Every day the scheduler materializes has one.
  TextColumn get programId => text()
      .references(Programs, #id, onDelete: KeyAction.cascade)
      .nullable()();

  /// Null for rest, cricket and custom days, which have no template behind
  /// them.
  TextColumn get sessionTemplateId => text()
      .references(SessionTemplates, #id, onDelete: KeyAction.setNull)
      .nullable()();

  /// Date-only `YYYY-MM-DD`, for the same reason as `programs.start_date`.
  TextColumn get date => text().withLength(min: 10, max: 10)();

  IntColumn get weekNumber => integer()();

  TextColumn get kind => textEnum<ScheduledSessionKind>()();

  TextColumn get status => textEnum<ScheduledSessionStatus>().withDefault(
    const Constant('upcoming'),
  )();

  IntColumn get plannedDurationMin => integer().nullable()();

  /// Why a gym day became something else — set when the user converts a day
  /// to cricket or rest, so a light week reads as intentional (ADR §8.2).
  TextColumn get overrideReason => text().nullable()();
}
