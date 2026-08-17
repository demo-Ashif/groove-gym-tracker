import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../../core/error/failure.dart';
import '../../../../domain/entities/exercise.dart';
import '../../../../domain/entities/plan.dart';
import '../../../../domain/entities/session_log.dart';

part 'active_session_state.freezed.dart';

@freezed
sealed class ActiveSessionState with _$ActiveSessionState {
  const ActiveSessionState._();

  const factory ActiveSessionState.loading() = ActiveSessionLoading;

  const factory ActiveSessionState.data({
    required SessionLog log,

    /// Null for a session logged against a day with no template — a cricket
    /// day someone decided to lift on. The screen falls back to whatever sets
    /// exist rather than refusing to open.
    SessionTemplate? template,

    required Map<String, Exercise> exercisesById,

    /// Last completed set per exercise, from earlier sessions. What a set chip
    /// pre-fills from.
    required Map<String, SetLog> previousSets,
  }) = ActiveSessionData;

  /// The session ended or was discarded — leave the screen.
  const factory ActiveSessionState.finished() = ActiveSessionFinished;

  const factory ActiveSessionState.failure(Failure failure) =
      ActiveSessionFailure;

  /// Sets prescribed by the template, which the summary measures against.
  int get plannedSets => switch (this) {
    ActiveSessionData(:final template) => template?.totalSets ?? 0,
    _ => 0,
  };
}
