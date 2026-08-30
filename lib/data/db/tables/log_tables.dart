import 'package:drift/drift.dart';

import '../../../domain/enums/training_enums.dart';
import 'catalog_tables.dart';
import 'plan_tables.dart';
import 'sync_columns.dart';

/// The **log** side of the model: what actually happened. Immutable once a
/// session is finalized — editing a template must never rewrite history
/// (ADR §8.2).

@TableIndex(name: 'idx_session_logs_scheduled', columns: {#scheduledSessionId})
@TableIndex(name: 'idx_session_logs_started', columns: {#startedAt})
@DataClassName('SessionLogRow')
class SessionLogs extends Table with SyncedRow {
  TextColumn get scheduledSessionId =>
      text().references(ScheduledSessions, #id, onDelete: KeyAction.cascade)();

  DateTimeColumn get startedAt => dateTime()();

  /// Null while the session is in progress. The active session is persisted
  /// on every set write, not on finish, so a process kill mid-workout loses
  /// nothing (ADR §9.4).
  DateTimeColumn get endedAt => dateTime().nullable()();

  RealColumn get sessionRpe => real().nullable()();

  /// 1–5 faces.
  IntColumn get energy => integer().nullable()();

  TextColumn get notes => text().nullable()();

  /// Snapshotted rather than joined to the nearest check-in: bodyweight at
  /// the time is what relative-strength maths needs, and check-ins are
  /// weekly at best.
  RealColumn get bodyweightAtTimeKg => real().nullable()();
}

/// The atom of the whole app.
///
/// `exerciseId` is denormalized here **deliberately** (ADR §4.3): charts query
/// it without walking the template tree, and history survives template edits
/// or deletions.
@TableIndex(name: 'idx_set_logs_session', columns: {#sessionLogId, #setIndex})
// The index every strength chart rides on (ADR §5.2).
@TableIndex(
  name: 'idx_set_logs_owner_exercise_created',
  columns: {#ownerId, #exerciseId, #createdAt},
)
@DataClassName('SetLogRow')
class SetLogs extends Table with SyncedRow {
  TextColumn get sessionLogId =>
      text().references(SessionLogs, #id, onDelete: KeyAction.cascade)();

  /// Null when the set wasn't prescribed — an extra set, or a substitution
  /// that no longer maps to its slot.
  TextColumn get exerciseTemplateId => text()
      .references(ExerciseTemplates, #id, onDelete: KeyAction.setNull)
      .nullable()();

  TextColumn get exerciseId =>
      text().references(Exercises, #id, onDelete: KeyAction.restrict)();

  /// 0-based position within the exercise.
  IntColumn get setIndex => integer()();

  TextColumn get side =>
      textEnum<SetSide>().withDefault(const Constant('both'))();

  TextColumn get status =>
      textEnum<SetStatus>().withDefault(const Constant('done'))();

  IntColumn get reps => integer().nullable()();
  RealColumn get weightKg => real().nullable()();
  IntColumn get durationSec => integer().nullable()();
  RealColumn get distanceM => real().nullable()();
  RealColumn get rpe => real().nullable()();

  /// Materialized on finalize so a chart doesn't recompute records on every
  /// paint. The `prs` table holds the detail.
  BoolColumn get isPr => boolean().withDefault(const Constant(false))();

  /// Required reading for Insights: a skip with a reason is data, a silent
  /// gap is guilt (ADR §20.1 item 7).
  TextColumn get skipReason => textEnum<SkipReason>().nullable()();

  /// What this set replaced. Logging the substitute against the catalog keeps
  /// charts honest instead of showing a gap (ADR §20.1 item 8).
  TextColumn get substitutedForExerciseId => text()
      .references(Exercises, #id, onDelete: KeyAction.restrict)
      .nullable()();

  TextColumn get note => text().nullable()();

  @override
  List<String> get customConstraints => [
    // A skipped set must say why; anything else must not carry a reason.
    "CHECK ((status = 'skipped') = (skip_reason IS NOT NULL))",
  ];
}

/// Derived and materialized: recomputed on session finalize rather than
/// scanned for on every chart paint (ADR §4.3).
@TableIndex(name: 'idx_prs_exercise_metric', columns: {#exerciseId, #metric})
@DataClassName('PrRow')
class Prs extends Table with SyncedRow {
  TextColumn get exerciseId =>
      text().references(Exercises, #id, onDelete: KeyAction.restrict)();

  TextColumn get metric => textEnum<PrMetric>()();

  RealColumn get value => real()();

  DateTimeColumn get achievedAt => dateTime()();

  /// The set that made it — a record with no evidence behind it is not worth
  /// showing.
  TextColumn get setLogId =>
      text().references(SetLogs, #id, onDelete: KeyAction.cascade)();
}
