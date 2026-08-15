import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/error/failure.dart';
import '../../../../domain/entities/plan.dart';
import '../../../../domain/repositories/plan_repository.dart';
import '../../../../core/error/result.dart';
import '../../../../domain/enums/training_enums.dart';
import '../../../../domain/repositories/schedule_repository.dart';
import '../../../../domain/values/schedule_pattern.dart';
import 'program_editor_state.dart';
import 'reorder.dart';

/// One program's tree, plus every edit the builder can make to it.
///
/// **Nothing here mutates local state.** Every write goes to the repository
/// and comes back through the same live query the screen is already watching,
/// so what is on screen is always what is in the database. That is also why a
/// failed write needs no rollback: the UI never moved.
class ProgramEditorCubit extends Cubit<ProgramEditorState> {
  ProgramEditorCubit({
    required PlanRepository repository,
    required ScheduleRepository scheduleRepository,
    required String programId,
  }) : _repository = repository,
       _schedule = scheduleRepository,
       _programId = programId,
       super(const ProgramEditorState.loading()) {
    _programSubscription = _repository.watchProgram(programId).listen(
      (program) {
        _loadedProgram = program;
        _programLoaded = true;
        _emit();
      },
      onError: (Object error) =>
          emit(ProgramEditorState.failure(Failure.fromException(error))),
    );

    _scheduleSubscription = _schedule.watchProgramSchedule(programId).listen(
      (days) {
        _scheduledDayCount = days.length;
        _emit();
      },
      onError: (Object error) =>
          emit(ProgramEditorState.failure(Failure.fromException(error))),
    );
  }

  final PlanRepository _repository;
  final ScheduleRepository _schedule;
  final String _programId;
  late final StreamSubscription<void> _programSubscription;
  late final StreamSubscription<void> _scheduleSubscription;

  Program? _loadedProgram;
  bool _programLoaded = false;
  int _scheduledDayCount = 0;

  /// The strip the user is editing. Held here rather than in the widget so it
  /// survives the program query re-emitting — adding a session must not wipe a
  /// half-drawn week.
  WeeklyPattern? _draft;

  Program? get _program => _loadedProgram;

  void _emit() {
    if (!_programLoaded) return;

    final program = _loadedProgram;
    if (program == null) {
      emit(const ProgramEditorState.gone());
      return;
    }

    // Seeded once. Re-seeding on every emit would discard the user's edits the
    // moment anything else in the program changed.
    _draft ??= switch (program.schedulePattern) {
      final WeeklyPattern weekly => weekly,
      // A cycle pattern has no week strip to draw; the editor starts from an
      // empty week rather than pretending to represent it.
      _ => const WeeklyPattern({}),
    };

    emit(
      ProgramEditorState.data(
        program: program,
        draftPattern: _draft!,
        scheduledDayCount: _scheduledDayCount,
      ),
    );
  }

  /// Sets what happens on one weekday. Passing null clears it back to rest.
  void assignDay(int weekday, DayAssignment? assignment) {
    final draft = _draft;
    if (draft == null) return;

    final days = Map<int, DayAssignment>.from(draft.days);
    if (assignment == null || assignment.kind == ScheduledSessionKind.rest) {
      // Absent and "rest" mean the same thing to the materializer; storing the
      // absence keeps the persisted pattern minimal.
      days.remove(weekday);
    } else {
      days[weekday] = assignment;
    }

    _draft = WeeklyPattern(days);
    _emit();
  }

  /// Expands the draft across the program and writes the difference.
  ///
  /// Returns the counts so the screen can say what actually happened rather
  /// than claiming success — "no days added" is a legitimate and useful
  /// outcome when nothing changed.
  Future<Result<({int added, int removed})>> commitSchedule() async {
    final draft = _draft;
    if (draft == null) {
      return const Err(UnexpectedFailure(debugMessage: 'No draft pattern'));
    }

    return _schedule.commitSchedule(programId: _programId, pattern: draft);
  }

  Future<Failure?> renameProgram(String name) async {
    final program = _program;
    if (program == null) return null;

    final result = await _repository.updateProgram(
      Program(
        id: program.id,
        name: name,
        startDate: program.startDate,
        endDate: program.endDate,
        isActive: program.isActive,
        notes: program.notes,
      ),
    );
    return result.failureOrNull;
  }

  Future<Failure?> setActive() async =>
      (await _repository.setActiveProgram(_programId)).failureOrNull;

  Future<Failure?> deleteProgram() async =>
      (await _repository.deleteProgram(_programId)).failureOrNull;

  Future<Failure?> addPhase({
    required String name,
    required int startWeek,
    required int endWeek,
  }) async {
    final result = await _repository.addPhase(
      programId: _programId,
      name: name,
      startWeek: startWeek,
      endWeek: endWeek,
    );
    return result.failureOrNull;
  }

  Future<Failure?> updatePhase(Phase phase) async =>
      (await _repository.updatePhase(phase)).failureOrNull;

  Future<Failure?> deletePhase(String id) async =>
      (await _repository.deletePhase(id)).failureOrNull;

  Future<Failure?> addSession({
    required String phaseId,
    required String code,
    required String title,
    int? dayOfWeek,
  }) async {
    final result = await _repository.addSession(
      phaseId: phaseId,
      code: code,
      title: title,
      dayOfWeek: dayOfWeek,
    );
    return result.failureOrNull;
  }

  Future<Failure?> deleteSession(String id) async =>
      (await _repository.deleteSession(id)).failureOrNull;

  /// Reorders phases from a drag. Takes the list as the user left it and
  /// hands the repository the full sibling order, so a drag that raced
  /// another edit cannot leave two rows claiming one slot.
  Future<Failure?> reorderPhases(int oldIndex, int newIndex) async {
    final phases = _program?.phases;
    if (phases == null) return null;

    final ids = reorderedIds(
      phases.map((p) => p.id).toList(),
      oldIndex,
      newIndex,
    );
    return (await _repository.reorderPhases(ids)).failureOrNull;
  }

  Future<Failure?> reorderSessions(
    Phase phase,
    int oldIndex,
    int newIndex,
  ) async {
    final ids = reorderedIds(
      phase.sessions.map((s) => s.id).toList(),
      oldIndex,
      newIndex,
    );
    return (await _repository.reorderSessions(ids)).failureOrNull;
  }

  @override
  Future<void> close() {
    _programSubscription.cancel();
    _scheduleSubscription.cancel();
    return super.close();
  }
}
