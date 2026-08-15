import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/error/failure.dart';
import '../../../../domain/entities/exercise.dart';
import '../../../../domain/entities/plan.dart';
import '../../../../domain/entities/session_log.dart';
import '../../../../domain/enums/training_enums.dart';
import '../../../../domain/repositories/exercise_repository.dart';
import '../../../../domain/repositories/log_repository.dart';
import '../../../../domain/repositories/plan_repository.dart';
import '../../../../domain/repositories/schedule_repository.dart';
import '../../../../domain/services/progression_service.dart';
import 'active_session_state.dart';

/// The logging loop (ADR §9.2).
///
/// **Nothing is held in memory waiting to be saved.** Every action writes
/// through to the repository and comes back on the session's live query, so a
/// process kill between two sets loses exactly nothing. That is also why the
/// screen has no save button and no dirty state to reconcile.
class ActiveSessionCubit extends Cubit<ActiveSessionState> {
  ActiveSessionCubit({
    required LogRepository logRepository,
    required PlanRepository planRepository,
    required ScheduleRepository scheduleRepository,
    required ExerciseRepository exerciseRepository,
    required String scheduledSessionId,
  }) : _log = logRepository,
       _plan = planRepository,
       _schedule = scheduleRepository,
       _exercises = exerciseRepository,
       _scheduledSessionId = scheduledSessionId,
       super(const ActiveSessionLoading()) {
    unawaited(_start());
  }

  final LogRepository _log;
  final PlanRepository _plan;
  final ScheduleRepository _schedule;
  final ExerciseRepository _exercises;
  final String _scheduledSessionId;

  StreamSubscription<void>? _logSubscription;
  StreamSubscription<void>? _catalogSubscription;

  SessionTemplate? _template;
  Map<String, Exercise> _catalog = const {};
  final Map<String, SetLog> _previousSets = {};
  SessionLog? _log0;

  DateTime? _restStartedAt;
  int _restSeconds = 0;

  bool _templateLoaded = false;
  bool _catalogLoaded = false;

  /// Loads the prescription once, then watches the log.
  ///
  /// The template is a one-shot read rather than a live query: a plan edit
  /// mid-session must not rewrite the workout under the user's hands. Template
  /// edits apply forward only (ADR §8.2).
  Future<void> _start() async {
    final scheduled = (await _schedule.findById(
      _scheduledSessionId,
    )).dataOrNull;
    if (scheduled == null) {
      emit(const ActiveSessionState.finished());
      return;
    }

    if (scheduled.sessionTemplateId case final templateId?) {
      final program = (await _plan.loadProgram(scheduled.programId)).dataOrNull;
      _template = program?.phases
          .expand((phase) => phase.sessions)
          .where((session) => session.id == templateId)
          .firstOrNull;
    }
    _templateLoaded = true;

    _catalogSubscription = _exercises.watchCatalog().listen((exercises) {
      _catalog = {for (final exercise in exercises) exercise.id: exercise};
      _catalogLoaded = true;
      _emit();
    }, onError: _onError);

    // Resume if a session is already running for this day; otherwise start
    // one. Both paths land on the same live query.
    final existing = await _log.watchActiveSession().first;
    if (existing == null ||
        existing.scheduledSessionId != _scheduledSessionId) {
      final started = await _log.startSession(
        scheduledSessionId: _scheduledSessionId,
      );
      if (started.failureOrNull case final failure?) {
        emit(ActiveSessionState.failure(failure));
        return;
      }
    }

    _logSubscription = _log.watchActiveSession().listen((log) {
      if (log == null) {
        // Finalized or discarded — including from another screen.
        emit(const ActiveSessionState.finished());
        return;
      }
      _log0 = log;
      unawaited(_loadPreviousSets(log));
      _emit();
    }, onError: _onError);
  }

  void _onError(Object error) =>
      emit(ActiveSessionState.failure(Failure.fromException(error)));

  /// Fetches last week's numbers for each exercise in the session, once each.
  Future<void> _loadPreviousSets(SessionLog log) async {
    final exerciseIds = <String>{
      for (final block in _template?.blocks ?? const <BlockTemplate>[])
        for (final slot in block.exercises) slot.exerciseId,
      for (final set in log.sets) set.exerciseId,
    };

    var changed = false;
    for (final exerciseId in exerciseIds) {
      if (_previousSets.containsKey(exerciseId)) continue;

      final previous = (await _log.lastCompletedSet(
        exerciseId: exerciseId,
        excludingSessionLogId: log.id,
      )).dataOrNull;

      if (previous != null) {
        _previousSets[exerciseId] = previous;
        changed = true;
      }
    }

    if (changed && !isClosed) _emit();
  }

  void _emit() {
    final log = _log0;
    if (!_templateLoaded || !_catalogLoaded || log == null) return;

    emit(
      ActiveSessionState.data(
        log: log,
        template: _template,
        exercisesById: _catalog,
        previousSets: Map.unmodifiable(_previousSets),
        restStartedAt: _restStartedAt,
        restSeconds: _restSeconds,
      ),
    );
  }

  /// What a set chip opens with: last session's numbers advanced by the
  /// prescription's progression rule.
  SetPrefill prefillFor(ExerciseTemplate slot, int setIndex) =>
      ProgressionService.suggest(
        template: slot,
        lastSet: _previousSets[slot.exerciseId],
        setIndex: setIndex,
      );

  /// One tap, one set. The 90% path.
  Future<Failure?> logSet({
    required ExerciseTemplate slot,
    required int setIndex,
    double? weightKg,
    int? reps,
    double? rpe,
    SetSide side = SetSide.both,
  }) async {
    final log = _log0;
    if (log == null) return null;

    final prefill = prefillFor(slot, setIndex);

    final result = await _log.logSet(
      sessionLogId: log.id,
      exerciseId: slot.exerciseId,
      setIndex: setIndex,
      exerciseTemplateId: slot.id,
      weightKg: weightKg ?? prefill.weightKg,
      reps: reps ?? prefill.reps,
      rpe: rpe,
      side: side,
    );

    if (result.isSuccess) _startRest(slot.restSeconds);
    return result.failureOrNull;
  }

  /// Completes every remaining set of an exercise at its target values. This
  /// is why a good session can be about ten taps (ADR §9.2).
  Future<Failure?> logAllAsPlanned(ExerciseTemplate slot) async {
    final log = _log0;
    if (log == null) return null;

    final logged = {
      for (final set in log.sets)
        if (set.exerciseId == slot.exerciseId) set.setIndex,
    };

    for (var index = 0; index < slot.targetSets; index++) {
      if (logged.contains(index)) continue;

      final prefill = prefillFor(slot, index);
      final result = await _log.logSet(
        sessionLogId: log.id,
        exerciseId: slot.exerciseId,
        setIndex: index,
        exerciseTemplateId: slot.id,
        weightKg: prefill.weightKg,
        reps: prefill.reps,
      );
      if (result.failureOrNull case final failure?) return failure;
    }

    _startRest(slot.restSeconds);
    return null;
  }

  Future<Failure?> skipSet({
    required ExerciseTemplate slot,
    required int setIndex,
    required SkipReason reason,
  }) async {
    final log = _log0;
    if (log == null) return null;

    final result = await _log.logSet(
      sessionLogId: log.id,
      exerciseId: slot.exerciseId,
      setIndex: setIndex,
      exerciseTemplateId: slot.id,
      status: SetStatus.skipped,
      skipReason: reason,
    );
    return result.failureOrNull;
  }

  Future<Failure?> clearSet(String setId) async =>
      (await _log.deleteSet(setId)).failureOrNull;

  // --- rest timer ----------------------------------------------------------

  /// Starts the rest interval. Stored as the moment it began, so a suspended
  /// app resumes at the right point rather than where it was paused.
  void _startRest(int seconds) {
    if (seconds <= 0) return;
    _restStartedAt = DateTime.now();
    _restSeconds = seconds;
    _emit();
  }

  void dismissRest() {
    _restStartedAt = null;
    _restSeconds = 0;
    _emit();
  }

  // --- ending --------------------------------------------------------------

  Future<Failure?> finalizeSession({
    double? sessionRpe,
    int? energy,
    String? notes,
  }) async {
    final log = _log0;
    if (log == null) return null;

    final result = await _log.finalizeSession(
      sessionLogId: log.id,
      scheduledSessionId: _scheduledSessionId,
      plannedSets: _template?.totalSets ?? 0,
      sessionRpe: sessionRpe,
      energy: energy,
      notes: notes,
    );
    return result.failureOrNull;
  }

  Future<Failure?> discardSession() async {
    final log = _log0;
    if (log == null) return null;

    final result = await _log.discardSession(
      sessionLogId: log.id,
      scheduledSessionId: _scheduledSessionId,
    );
    return result.failureOrNull;
  }

  @override
  Future<void> close() {
    _logSubscription?.cancel();
    _catalogSubscription?.cancel();
    return super.close();
  }
}
