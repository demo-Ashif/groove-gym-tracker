import 'package:equatable/equatable.dart';

import '../enums/training_enums.dart';

/// What actually happened (ADR §4.3 `session_logs` / `set_logs`).
///
/// Immutable once finalized: editing a template must never rewrite history
/// (ADR §8.2). The active session is persisted on **every set write**, not on
/// finish, so a process kill mid-workout loses nothing (ADR §9.4).

/// One set. The atom of the whole app.
class SetLog extends Equatable {
  const SetLog({
    required this.id,
    required this.sessionLogId,
    required this.exerciseId,
    required this.setIndex,
    this.exerciseTemplateId,
    this.side = SetSide.both,
    this.status = SetStatus.done,
    this.reps,
    this.weightKg,
    this.durationSec,
    this.distanceM,
    this.rpe,
    this.isPr = false,
    this.skipReason,
    this.substitutedForExerciseId,
    this.note,
  });

  final String id;
  final String sessionLogId;

  /// Null when the set wasn't prescribed — an extra set, or a substitution
  /// that no longer maps to its slot.
  final String? exerciseTemplateId;

  /// Denormalized on purpose: charts query it without walking the template
  /// tree, and history survives template edits (ADR §4.3).
  final String exerciseId;

  /// 0-based position within the exercise.
  final int setIndex;

  final SetSide side;
  final SetStatus status;

  final int? reps;
  final double? weightKg;
  final int? durationSec;
  final double? distanceM;
  final double? rpe;

  final bool isPr;

  /// Required when [status] is skipped — a skip with a reason is data, a
  /// silent gap is guilt (ADR §20.1 item 7).
  final SkipReason? skipReason;

  final String? substitutedForExerciseId;
  final String? note;

  /// Counts towards adherence. A partial set was worked but under target, and
  /// deliberately does not count as done.
  bool get isCompleted => status == SetStatus.done;

  bool get isSkipped => status == SetStatus.skipped;

  bool get hasLoad => weightKg != null && reps != null;

  @override
  List<Object?> get props => [
    id,
    sessionLogId,
    exerciseTemplateId,
    exerciseId,
    setIndex,
    side,
    status,
    reps,
    weightKg,
    durationSec,
    distanceM,
    rpe,
    isPr,
    skipReason,
    substitutedForExerciseId,
    note,
  ];
}

/// One session, with the sets logged in it.
class SessionLog extends Equatable {
  const SessionLog({
    required this.id,
    required this.scheduledSessionId,
    required this.startedAt,
    this.endedAt,
    this.sessionRpe,
    this.energy,
    this.notes,
    this.bodyweightAtTimeKg,
    this.sets = const [],
  });

  final String id;
  final String scheduledSessionId;
  final DateTime startedAt;

  /// Null while the session is in progress — which is also how the app finds
  /// a session to resume after a cold start.
  final DateTime? endedAt;

  final double? sessionRpe;

  /// 1–5 faces.
  final int? energy;

  final String? notes;

  /// Snapshotted rather than joined to the nearest check-in: bodyweight at the
  /// time is what relative-strength maths needs.
  final double? bodyweightAtTimeKg;

  final List<SetLog> sets;

  bool get isActive => endedAt == null;

  Duration get duration => (endedAt ?? DateTime.now()).difference(startedAt);

  int get completedSets => sets.where((set) => set.isCompleted).length;

  int get skippedSets => sets.where((set) => set.isSkipped).length;

  /// Sets logged for one exercise, in the order they were performed.
  List<SetLog> setsFor(String exerciseId) =>
      sets.where((set) => set.exerciseId == exerciseId).toList()
        ..sort((a, b) => a.setIndex.compareTo(b.setIndex));

  @override
  List<Object?> get props => [
    id,
    scheduledSessionId,
    startedAt,
    endedAt,
    sessionRpe,
    energy,
    notes,
    bodyweightAtTimeKg,
    sets,
  ];
}
