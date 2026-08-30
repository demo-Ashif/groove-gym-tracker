import 'package:drift/drift.dart';

import '../../../domain/enums/training_enums.dart';
import '../app_database.dart';
import '../tables/log_tables.dart';
import '../tables/plan_tables.dart';

part 'log_dao.g.dart';

/// A session and its sets, before the mapper joins them up.
typedef SessionLogRows = ({SessionLogRow log, List<SetLogRow> sets});

/// A finished session with the day it was logged against, for the history
/// list. The title comes from the template so a row reads "Push + Core"
/// rather than a bare date.
typedef SessionHistoryRows = ({
  SessionLogRow log,
  List<SetLogRow> sets,
  String? title,
});

/// Reads and writes what actually happened.
///
/// **Every write here is a write to disk, immediately.** The active session is
/// persisted on each set, not on finish (ADR §9.4), because the phone will be
/// backgrounded, the screen will lock, and the OS will eventually kill the
/// process mid-workout. Nothing may be held in memory waiting for a "save".
@DriftAccessor(
  tables: [SessionLogs, SetLogs, ScheduledSessions, SessionTemplates],
)
class LogDao extends DatabaseAccessor<AppDatabase> with _$LogDaoMixin {
  LogDao(super.attachedDatabase);

  /// The session in progress, if any. This is how a cold start finds a workout
  /// to resume, and what the logging screen renders from.
  ///
  /// **The join is load-bearing, not an optimisation.** A drift stream only
  /// re-runs when one of the tables *it reads* is written. Selecting from
  /// `session_logs` and fetching the sets separately makes the stream blind to
  /// `set_logs`, so logging a set — which touches nothing else — never
  /// refreshes it and the screen shows a workout frozen at its first frame.
  Stream<SessionLogRows?> watchActiveSession() {
    final query =
        select(sessionLogs).join([
            leftOuterJoin(
              setLogs,
              setLogs.sessionLogId.equalsExp(sessionLogs.id) &
                  setLogs.deletedAt.isNull(),
            ),
          ])
          ..where(sessionLogs.endedAt.isNull() & sessionLogs.deletedAt.isNull())
          // Newest session first, so the fold below can stop at the moment the
          // id changes. `limit` cannot be used here: it would cap *joined*
          // rows, which would silently drop every set after the first.
          ..orderBy([
            OrderingTerm.desc(sessionLogs.startedAt),
            OrderingTerm.asc(setLogs.setIndex),
          ]);

    return query.watch().map(_firstSession);
  }

  /// One session and its sets, live. Same join, same reason — a set written
  /// while the screen is open has to reach it.
  Stream<SessionLogRows?> watchSession(String id) {
    final query =
        select(sessionLogs).join([
            leftOuterJoin(
              setLogs,
              setLogs.sessionLogId.equalsExp(sessionLogs.id) &
                  setLogs.deletedAt.isNull(),
            ),
          ])
          ..where(sessionLogs.id.equals(id) & sessionLogs.deletedAt.isNull())
          ..orderBy([OrderingTerm.asc(setLogs.setIndex)]);

    return query.watch().map(_firstSession);
  }

  /// Folds joined rows into the first session and the sets belonging to it.
  ///
  /// A left join repeats the session once per set, and emits a single row with
  /// a null set when there are none yet — which is exactly the state a session
  /// opens in.
  SessionLogRows? _firstSession(List<TypedResult> rows) {
    if (rows.isEmpty) return null;

    final log = rows.first.readTable(sessionLogs);
    final sets = <SetLogRow>[];

    for (final row in rows) {
      // Rows are ordered so one session's are contiguous; anything past them
      // belongs to an older session that this query is not reporting on.
      if (row.readTable(sessionLogs).id != log.id) break;

      final set = row.readTableOrNull(setLogs);
      if (set != null) sets.add(set);
    }

    return (log: log, sets: sets);
  }

  Future<SessionLogRows?> loadSession(String id) async {
    final log =
        await (select(sessionLogs)
              ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
            .getSingleOrNull();
    if (log == null) return null;
    return (log: log, sets: await _setsFor(log.id));
  }

  /// The most recently finished session for a scheduled day, for the "last
  /// session" recap.
  Future<SessionLogRows?> loadLatestForScheduled(String scheduledId) async {
    final log =
        await (select(sessionLogs)
              ..where(
                (row) =>
                    row.scheduledSessionId.equals(scheduledId) &
                    row.deletedAt.isNull(),
              )
              ..orderBy([(row) => OrderingTerm.desc(row.startedAt)])
              ..limit(1))
            .getSingleOrNull();
    if (log == null) return null;
    return (log: log, sets: await _setsFor(log.id));
  }

  /// Every finished session, newest first, with the day and template behind
  /// it.
  ///
  /// In-progress sessions are excluded: one is already surfaced by
  /// [watchActiveSession] as something to resume, and a history list is a list
  /// of things that happened.
  ///
  /// The template join is a **left** join on purpose. A session logged against
  /// a cricket day has no template, and a program deleted since then leaves
  /// the row pointing at nothing — neither is a reason to drop a workout the
  /// user actually did out of their own history.
  Stream<List<SessionHistoryRows>> watchFinishedSessions({int limit = 200}) {
    final query =
        select(sessionLogs).join([
            leftOuterJoin(
              scheduledSessions,
              scheduledSessions.id.equalsExp(sessionLogs.scheduledSessionId),
            ),
            leftOuterJoin(
              sessionTemplates,
              sessionTemplates.id.equalsExp(
                scheduledSessions.sessionTemplateId,
              ),
            ),
          ])
          ..where(
            sessionLogs.endedAt.isNotNull() & sessionLogs.deletedAt.isNull(),
          )
          ..orderBy([OrderingTerm.desc(sessionLogs.startedAt)])
          ..limit(limit);

    return query.watch().asyncMap((rows) async {
      final result = <SessionHistoryRows>[];
      for (final row in rows) {
        final log = row.readTable(sessionLogs);
        result.add((
          log: log,
          sets: await _setsFor(log.id),
          title: row.readTableOrNull(sessionTemplates)?.title,
        ));
      }
      return result;
    });
  }

  Future<List<SetLogRow>> _setsFor(String sessionLogId) {
    return (select(setLogs)
          ..where(
            (row) =>
                row.sessionLogId.equals(sessionLogId) & row.deletedAt.isNull(),
          )
          ..orderBy([(row) => OrderingTerm(expression: row.setIndex)]))
        .get();
  }

  /// Starts a session and marks its day in progress, in one transaction — a
  /// log with no matching day status is a session the calendar doesn't know
  /// about.
  Future<SessionLogRow> startSession({
    required String scheduledSessionId,
    required DateTime startedAt,
    double? bodyweightKg,
  }) async {
    return transaction(() async {
      final log = await into(sessionLogs).insertReturning(
        SessionLogsCompanion.insert(
          scheduledSessionId: scheduledSessionId,
          startedAt: startedAt,
          bodyweightAtTimeKg: Value(bodyweightKg),
        ),
      );

      await (update(
        scheduledSessions,
      )..where((row) => row.id.equals(scheduledSessionId))).write(
        ScheduledSessionsCompanion(
          status: const Value(ScheduledSessionStatus.inProgress),
          updatedAt: Value(DateTime.now()),
          syncState: const Value(SyncState.pendingUpdate),
        ),
      );

      return log;
    });
  }

  /// Writes a set, replacing whatever was at that position.
  ///
  /// Keyed by (session, exercise, index) rather than by row id: tapping the
  /// same chip twice must correct the set, not add a second one.
  Future<SetLogRow> upsertSet({
    required String sessionLogId,
    required String exerciseId,
    required int setIndex,
    String? exerciseTemplateId,
    SetSide side = SetSide.both,
    SetStatus status = SetStatus.done,
    int? reps,
    double? weightKg,
    int? durationSec,
    double? rpe,
    SkipReason? skipReason,
    String? note,
  }) async {
    return transaction(() async {
      final existing =
          await (select(setLogs)..where(
                (row) =>
                    row.sessionLogId.equals(sessionLogId) &
                    row.exerciseId.equals(exerciseId) &
                    row.setIndex.equals(setIndex) &
                    row.deletedAt.isNull(),
              ))
              .getSingleOrNull();

      if (existing != null) {
        await (update(
          setLogs,
        )..where((row) => row.id.equals(existing.id))).write(
          SetLogsCompanion(
            exerciseTemplateId: Value(exerciseTemplateId),
            side: Value(side),
            status: Value(status),
            reps: Value(reps),
            weightKg: Value(weightKg),
            durationSec: Value(durationSec),
            rpe: Value(rpe),
            skipReason: Value(skipReason),
            note: Value(note),
            updatedAt: Value(DateTime.now()),
            syncState: const Value(SyncState.pendingUpdate),
          ),
        );

        return (select(
          setLogs,
        )..where((row) => row.id.equals(existing.id))).getSingle();
      }

      return into(setLogs).insertReturning(
        SetLogsCompanion.insert(
          sessionLogId: sessionLogId,
          exerciseId: exerciseId,
          setIndex: setIndex,
          exerciseTemplateId: Value(exerciseTemplateId),
          side: Value(side),
          status: Value(status),
          reps: Value(reps),
          weightKg: Value(weightKg),
          durationSec: Value(durationSec),
          rpe: Value(rpe),
          skipReason: Value(skipReason),
          note: Value(note),
        ),
      );
    });
  }

  Future<void> deleteSet(String id) async {
    final now = DateTime.now();
    await (update(setLogs)..where((row) => row.id.equals(id))).write(
      SetLogsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        syncState: const Value(SyncState.pendingDelete),
      ),
    );
  }

  /// The last completed set of an exercise, from any earlier session. Drives
  /// the pre-filled values on a set chip.
  Future<SetLogRow?> lastCompletedSet({
    required String exerciseId,
    required String excludingSessionLogId,
  }) {
    return (select(setLogs)
          ..where(
            (row) =>
                row.exerciseId.equals(exerciseId) &
                row.sessionLogId.equals(excludingSessionLogId).not() &
                row.status.equalsValue(SetStatus.done) &
                row.deletedAt.isNull(),
          )
          ..orderBy([(row) => OrderingTerm.desc(row.createdAt)])
          ..limit(1))
        .getSingleOrNull();
  }

  /// Ends a session and settles its day's status, in one transaction.
  ///
  /// [status] is decided by the caller from what was actually logged —
  /// `completed` or `partial` — because "did enough happen" is a domain
  /// question, not a storage one.
  Future<void> finalizeSession({
    required String sessionLogId,
    required String scheduledSessionId,
    required DateTime endedAt,
    required ScheduledSessionStatus status,
    double? sessionRpe,
    int? energy,
    String? notes,
  }) async {
    await transaction(() async {
      final now = DateTime.now();

      await (update(
        sessionLogs,
      )..where((row) => row.id.equals(sessionLogId))).write(
        SessionLogsCompanion(
          endedAt: Value(endedAt),
          sessionRpe: Value(sessionRpe),
          energy: Value(energy),
          notes: Value(notes),
          updatedAt: Value(now),
          syncState: const Value(SyncState.pendingUpdate),
        ),
      );

      await (update(
        scheduledSessions,
      )..where((row) => row.id.equals(scheduledSessionId))).write(
        ScheduledSessionsCompanion(
          status: Value(status),
          updatedAt: Value(now),
          syncState: const Value(SyncState.pendingUpdate),
        ),
      );
    });
  }

  /// Abandons a session, returning its day to upcoming. For a session started
  /// by accident — the alternative is a phantom in-progress workout that
  /// blocks the Today screen forever.
  Future<void> discardSession({
    required String sessionLogId,
    required String scheduledSessionId,
  }) async {
    await transaction(() async {
      final now = DateTime.now();

      await (update(
        sessionLogs,
      )..where((row) => row.id.equals(sessionLogId))).write(
        SessionLogsCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
          syncState: const Value(SyncState.pendingDelete),
        ),
      );

      await (update(
        setLogs,
      )..where((row) => row.sessionLogId.equals(sessionLogId))).write(
        SetLogsCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
          syncState: const Value(SyncState.pendingDelete),
        ),
      );

      await (update(
        scheduledSessions,
      )..where((row) => row.id.equals(scheduledSessionId))).write(
        ScheduledSessionsCompanion(
          status: const Value(ScheduledSessionStatus.upcoming),
          updatedAt: Value(now),
          syncState: const Value(SyncState.pendingUpdate),
        ),
      );
    });
  }
}
