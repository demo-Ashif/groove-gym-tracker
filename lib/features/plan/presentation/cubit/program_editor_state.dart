import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../../core/error/failure.dart';
import '../../../../domain/entities/plan.dart';
import '../../../../domain/values/schedule_pattern.dart';

part 'program_editor_state.freezed.dart';

/// [ProgramEditorGone] is not an error branch — it is the normal outcome of
/// deleting the program you are editing, and the screen's cue to leave rather
/// than sit on rows that no longer exist.
@freezed
sealed class ProgramEditorState with _$ProgramEditorState {
  const ProgramEditorState._();

  const factory ProgramEditorState.loading() = ProgramEditorLoading;

  const factory ProgramEditorState.data({
    required Program program,

    /// The week strip as the user currently has it, which is not necessarily
    /// what is committed. Seeded from the program's stored pattern the first
    /// time it loads.
    required WeeklyPattern draftPattern,

    /// How many dated days the committed calendar holds.
    required int scheduledDayCount,
  }) = ProgramEditorData;

  const factory ProgramEditorState.gone() = ProgramEditorGone;

  const factory ProgramEditorState.failure(Failure failure) =
      ProgramEditorFailure;

  /// True when the strip has been edited but not applied to the calendar.
  /// Drives the "not committed yet" badge, so the user is never left guessing
  /// whether their change reached the dates.
  bool get hasUncommittedSchedule => switch (this) {
    ProgramEditorData(:final program, :final draftPattern) =>
      program.schedulePattern != draftPattern,
    _ => false,
  };
}
