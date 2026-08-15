import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../../core/error/failure.dart';
import '../../../../domain/entities/exercise.dart';
import '../../../../domain/entities/plan.dart';

part 'session_editor_state.freezed.dart';

/// The session being edited, plus the catalog rows its slots point at.
///
/// The catalog travels *with* the session rather than being looked up per row:
/// an exercise slot stores only an id, and a list that resolved each name on
/// its own would fire a query per row.
@freezed
sealed class SessionEditorState with _$SessionEditorState {
  const factory SessionEditorState.loading() = SessionEditorLoading;

  const factory SessionEditorState.data({
    required SessionTemplate session,
    required Map<String, Exercise> exercisesById,
  }) = SessionEditorData;

  /// The session or its program was deleted — leave the screen.
  const factory SessionEditorState.gone() = SessionEditorGone;

  const factory SessionEditorState.failure(Failure failure) =
      SessionEditorFailure;
}
