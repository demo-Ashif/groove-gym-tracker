import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/error/failure.dart';
import '../../../../domain/entities/exercise.dart';
import '../../../../domain/entities/plan.dart';
import '../../../../domain/enums/training_enums.dart';
import '../../../../domain/repositories/exercise_repository.dart';
import '../../../../domain/repositories/plan_repository.dart';
import '../../../../domain/values/progression_rule.dart';
import 'reorder.dart';
import 'session_editor_state.dart';

/// One session's blocks and exercise slots.
///
/// Two live queries feed it — the program tree and the exercise catalog — and
/// it emits only once both have arrived, so the screen never renders a row
/// whose exercise name is still missing.
class SessionEditorCubit extends Cubit<SessionEditorState> {
  SessionEditorCubit({
    required PlanRepository planRepository,
    required ExerciseRepository exerciseRepository,
    required String programId,
    required String sessionId,
  }) : _plan = planRepository,
       _sessionId = sessionId,
       super(const SessionEditorLoading()) {
    _planSubscription = _plan.watchProgram(programId).listen(
      (program) {
        _session = _findSession(program);
        _emit();
      },
      onError: (Object error) =>
          emit(SessionEditorState.failure(Failure.fromException(error))),
    );

    _catalogSubscription = exerciseRepository.watchCatalog().listen(
      (exercises) {
        _catalog = {for (final exercise in exercises) exercise.id: exercise};
        _emit();
      },
      onError: (Object error) =>
          emit(SessionEditorState.failure(Failure.fromException(error))),
    );
  }

  final PlanRepository _plan;
  final String _sessionId;

  late final StreamSubscription<void> _planSubscription;
  late final StreamSubscription<void> _catalogSubscription;

  SessionTemplate? _session;
  Map<String, Exercise>? _catalog;

  /// True once the plan query has answered — distinguishes "still loading" from
  /// "the session is gone", which look identical if you only check for null.
  bool _planLoaded = false;

  SessionTemplate? _findSession(Program? program) {
    _planLoaded = true;
    if (program == null) return null;

    for (final phase in program.phases) {
      for (final session in phase.sessions) {
        if (session.id == _sessionId) return session;
      }
    }
    return null;
  }

  void _emit() {
    final catalog = _catalog;
    if (!_planLoaded || catalog == null) return;

    final session = _session;
    emit(
      session == null
          ? const SessionEditorState.gone()
          : SessionEditorState.data(session: session, exercisesById: catalog),
    );
  }

  Future<Failure?> addBlock({
    required BlockKind kind,
    required String title,
  }) async {
    final result = await _plan.addBlock(
      sessionTemplateId: _sessionId,
      kind: kind,
      title: title,
    );
    return result.failureOrNull;
  }

  Future<Failure?> updateBlock(BlockTemplate block) async =>
      (await _plan.updateBlock(block)).failureOrNull;

  Future<Failure?> deleteBlock(String id) async =>
      (await _plan.deleteBlock(id)).failureOrNull;

  Future<Failure?> addExercise({
    required String blockTemplateId,
    required String exerciseId,
    required int targetSets,
    int? targetReps,
    int? targetDurationSec,
    double? targetLoadKg,
    int restSeconds = 90,
    bool perSide = false,
    ProgressionRule progression = const ProgressionRule.fixed(),
  }) async {
    final result = await _plan.addExercise(
      blockTemplateId: blockTemplateId,
      exerciseId: exerciseId,
      targetSets: targetSets,
      targetReps: targetReps,
      targetDurationSec: targetDurationSec,
      targetLoadKg: targetLoadKg,
      restSeconds: restSeconds,
      perSide: perSide,
      progression: progression,
    );
    return result.failureOrNull;
  }

  Future<Failure?> updateExercise(ExerciseTemplate exercise) async =>
      (await _plan.updateExercise(exercise)).failureOrNull;

  Future<Failure?> deleteExercise(String id) async =>
      (await _plan.deleteExercise(id)).failureOrNull;

  Future<Failure?> reorderBlocks(int oldIndex, int newIndex) async {
    final blocks = _session?.blocks;
    if (blocks == null) return null;

    final ids = reorderedIds(
      blocks.map((b) => b.id).toList(),
      oldIndex,
      newIndex,
    );
    return (await _plan.reorderBlocks(ids)).failureOrNull;
  }

  Future<Failure?> reorderExercises(
    BlockTemplate block,
    int oldIndex,
    int newIndex,
  ) async {
    final ids = reorderedIds(
      block.exercises.map((e) => e.id).toList(),
      oldIndex,
      newIndex,
    );
    return (await _plan.reorderExercises(ids)).failureOrNull;
  }

  @override
  Future<void> close() {
    _planSubscription.cancel();
    _catalogSubscription.cancel();
    return super.close();
  }
}
