import 'package:drift/drift.dart';

import '../../../domain/enums/training_enums.dart';
import '../app_database.dart';
import '../tables/log_tables.dart';
import '../tables/plan_tables.dart';

part 'log_dao.g.dart';

/// A session and its sets, before the mapper joins them up.
typedef SessionLogRows = ({SessionLogRow log, List<SetLogRow> sets});

/// Reads and writes what actually happened.
///
/// **Every write here is a write to disk, immediately.** The active session is
/// persisted on each set, not on finish (ADR §9.4), because the phone will be
/// backgrounded, the screen will lock, and the OS will eventually kill the
/// process mid-workout. Nothing may be held in memory waiting for a "save".
@DriftAccessor(tables: [SessionLogs, SetLogs, ScheduledSessions])
class LogDao extends DatabaseAccessor<AppDatabase> with _$LogDaoMixin {
  LogDao(super.attachedDatabase);

  /// The session in progress, if any. This is how a cold start finds a workout
  /// to resume.
  Stream<SessionLogRows?> watchActiveSession() {
    return (select(sessionLogs)
          ..where((row) => row.endedAt.isNull() & row.deletedAt.isNull())
          ..orderBy([(row) => OrderingTerm.desc(row.startedAt)])
          ..limit(1))
        .watchSingleOrNull()
        .asyncMap((log) async {
          if (log == null) return null;
          return (log: log, sets: await _setsFor(log.id));
        });
  }

  Stream<SessionLogRows?> watchSession(String id) {
    return (select(sessionLogs)
          ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
        .watchSingleOrNull()
        .asyncMap((log) async {
          if (log == null) return null;
          return (log: log, sets: await _setsFor(log.id));
        });
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
