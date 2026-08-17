import '../../core/error/app_exception.dart';
import '../../core/error/result.dart';
import '../../domain/entities/session_log.dart';
import '../../domain/enums/training_enums.dart';
import '../../domain/repositories/log_repository.dart';
import '../db/daos/log_dao.dart';
import '../mappers/session_log_mapper.dart';

/// Drift-backed logging loop.
class LogRepositoryImpl implements LogRepository {
  const LogRepositoryImpl(this._dao);

  final LogDao _dao;

  @override
  Stream<SessionLog?> watchActiveSession() =>
      _dao.watchActiveSession().map((rows) => rows?.toEntity());

  @override
  Stream<SessionLog?> watchSession(String id) =>
      _dao.watchSession(id).map((rows) => rows?.toEntity());

  @override
  Stream<List<SessionHistoryEntry>> watchFinishedSessions({int limit = 200}) =>
      _dao
          .watchFinishedSessions(limit: limit)
          .map(
            (rows) => rows.map((row) => row.toEntity()).toList(growable: false),
          );

  @override
  Future<Result<SessionLog?>> latestForScheduled(String scheduledSessionId) =>
      Result.guard(
        () async =>
            (await _dao.loadLatestForScheduled(scheduledSessionId))?.toEntity(),
      );

  @override
  Future<Result<SessionLog>> startSession({
    required String scheduledSessionId,
    DateTime? startedAt,
    double? bodyweightKg,
  }) => Result.guard(() async {
    final row = await _dao.startSession(
      scheduledSessionId: scheduledSessionId,
      startedAt: startedAt ?? DateTime.now(),
      bodyweightKg: bodyweightKg,
    );

    final loaded = await _dao.loadSession(row.id);
    if (loaded == null) {
      throw const CacheException('Session could not be read back');
    }
    return loaded.toEntity();
  });

  @override
  Future<Result<SetLog>> logSet({
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
  }) => Result.guard(() async {
    // Mirrors the schema's CHECK constraint, so a bad call fails as a
    // validation error rather than as a raw SQLite exception.
    if (status == SetStatus.skipped && skipReason == null) {
      throw const ParseException('A skipped set must carry a reason');
    }
    if (status != SetStatus.skipped && skipReason != null) {
      throw const ParseException('Only a skipped set may carry a reason');
    }

    final row = await _dao.upsertSet(
      sessionLogId: sessionLogId,
      exerciseId: exerciseId,
      setIndex: setIndex,
      exerciseTemplateId: exerciseTemplateId,
      side: side,
      status: status,
      reps: reps,
      weightKg: weightKg,
      durationSec: durationSec,
      rpe: rpe,
      skipReason: skipReason,
      note: note,
    );

    return row.toEntity();
  });

  @override
  Future<Result<void>> deleteSet(String id) =>
      Result.guard(() => _dao.deleteSet(id));

  @override
  Future<Result<SetLog?>> lastCompletedSet({
    required String exerciseId,
    required String excludingSessionLogId,
  }) => Result.guard(
    () async => (await _dao.lastCompletedSet(
      exerciseId: exerciseId,
      excludingSessionLogId: excludingSessionLogId,
    ))?.toEntity(),
  );

  @override
  Future<Result<void>> finalizeSession({
    required String sessionLogId,
    required String scheduledSessionId,
    required int plannedSets,
    double? sessionRpe,
    int? energy,
    String? notes,
  }) => Result.guard(() async {
    final session = await _dao.loadSession(sessionLogId);
    if (session == null) {
      throw const CacheException('Session not found');
    }

    final log = session.toEntity();

    await _dao.finalizeSession(
      sessionLogId: sessionLogId,
      scheduledSessionId: scheduledSessionId,
      endedAt: DateTime.now(),
      status: settleStatus(
        completedSets: log.completedSets,
        plannedSets: plannedSets,
      ),
      sessionRpe: sessionRpe,
      energy: energy,
      notes: notes,
    );
  });

  @override
  Future<Result<void>> discardSession({
    required String sessionLogId,
    required String scheduledSessionId,
  }) => Result.guard(
    () => _dao.discardSession(
      sessionLogId: sessionLogId,
      scheduledSessionId: scheduledSessionId,
    ),
  );
}

/// How a finished session settles its day.
///
/// `partial` exists so a session that was cut short reads differently from one
/// that was seen through — the two look identical in a bare completion count,
/// and Insights needs to tell them apart (ADR §4.4).
///
/// Nothing logged at all is `skipped`: starting a session and walking out is
/// not a partial workout.
ScheduledSessionStatus settleStatus({
  required int completedSets,
  required int plannedSets,
}) {
  if (completedSets == 0) return ScheduledSessionStatus.skipped;
  if (plannedSets == 0) return ScheduledSessionStatus.completed;

  // Two thirds of the prescribed work is the line between "did the session"
  // and "did some of it". Arbitrary, but it has to be somewhere, and it is
  // one constant rather than a rule scattered across screens.
  return completedSets / plannedSets >= _completionThreshold
      ? ScheduledSessionStatus.completed
      : ScheduledSessionStatus.partial;
}

const _completionThreshold = 2 / 3;
