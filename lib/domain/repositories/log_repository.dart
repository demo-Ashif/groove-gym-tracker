import '../../core/error/result.dart';
import '../entities/session_log.dart';
import '../enums/training_enums.dart';

/// The logging loop (ADR §9).
abstract interface class LogRepository {
  /// The session in progress, if any — how a cold start finds a workout to
  /// resume (ADR §9.4).
  Stream<SessionLog?> watchActiveSession();

  Stream<SessionLog?> watchSession(String id);

  /// Every finished session, newest first — the history list.
  ///
  /// Excludes the session in progress: that one is offered as something to
  /// resume, and history is a record of what happened.
  Stream<List<SessionHistoryEntry>> watchFinishedSessions({int limit});

  /// The most recent session logged against a scheduled day, for the recap.
  Future<Result<SessionLog?>> latestForScheduled(String scheduledSessionId);

  /// Starts a session on [scheduledSessionId].
  ///
  /// [startedAt] defaults to now. Backfilling a past workout passes the date
  /// it actually happened, so history sorts and charts by when the training
  /// was done rather than by when it was typed in.
  Future<Result<SessionLog>> startSession({
    required String scheduledSessionId,
    DateTime? startedAt,
    double? bodyweightKg,
  });

  /// Writes one set. Keyed by position, so confirming the same chip twice
  /// corrects the set rather than adding another.
  Future<Result<SetLog>> logSet({
    required String sessionLogId,
    required String exerciseId,
    required int setIndex,
    String? exerciseTemplateId,
    SetSide side,
    SetStatus status,
    int? reps,
    double? weightKg,
    int? durationSec,
    double? rpe,
    SkipReason? skipReason,
    String? note,
  });

  Future<Result<void>> deleteSet(String id);

  /// The last completed set of an exercise from an earlier session — what a
  /// set chip pre-fills from.
  Future<Result<SetLog?>> lastCompletedSet({
    required String exerciseId,
    required String excludingSessionLogId,
  });

  /// Ends the session and settles its day.
  ///
  /// Whether the day counts as completed or partial is decided from what was
  /// logged, not passed in — "did enough happen" is a domain question.
  Future<Result<void>> finalizeSession({
    required String sessionLogId,
    required String scheduledSessionId,
    required int plannedSets,
    double? sessionRpe,
    int? energy,
    String? notes,
  });

  /// Abandons a session and returns its day to upcoming.
  Future<Result<void>> discardSession({
    required String sessionLogId,
    required String scheduledSessionId,
  });
}
