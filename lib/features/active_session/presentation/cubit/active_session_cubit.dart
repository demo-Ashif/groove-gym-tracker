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
import '../../../../domain/values/calendar_date.dart';
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

    // Both are needed: a backfilled day has neither a program nor a template,
    // and logs freeform against the catalog instead.
    if (scheduled.sessionTemplateId case final templateId?) {
      final programId = scheduled.programId;
      final program = programId == null
          ? null
          : (await _plan.loadProgram(programId)).dataOrNull;
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
        // A day in the past is a backfill: the session is stamped with the
        // date it happened, not the moment it was typed in, or history sorts
        // by data entry and every chart reads wrong.
        startedAt: _startedAtFor(scheduled.date),
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

  /// When to stamp a session that is being started for [date].
  ///
  /// Today keeps the real clock, so duration is measured properly. A past day
  /// gets midday on that date — a defensible "sometime that day" that is well
  /// clear of both midnight boundaries in any timezone.
  DateTime? _startedAtFor(CalendarDate date) {
    if (date == CalendarDate.today()) return null;
    return DateTime(date.year, date.month, date.day, 12);
  }

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
  ///
  /// A time-based slot writes only a duration. Its prescription has no load
  /// and no reps, so pre-filling either would invent numbers that go straight
  /// into tonnage and e1RM charts as fact.
  Future<Failure?> logSet({
    required ExerciseTemplate slot,
    required int setIndex,
    double? weightKg,
    int? reps,
    int? durationSec,
    double? rpe,
    SetSide side = SetSide.both,
  }) async {
    final log = _log0;
    if (log == null) return null;

    final prefill = prefillFor(slot, setIndex);
    final isTimeBased = slot.isTimeBased;

    final result = await _log.logSet(
      sessionLogId: log.id,
      exerciseId: slot.exerciseId,
      setIndex: setIndex,
      exerciseTemplateId: slot.id,
      weightKg: isTimeBased ? null : (weightKg ?? prefill.weightKg),
      reps: isTimeBased ? null : (reps ?? prefill.reps),
      durationSec: isTimeBased ? (durationSec ?? slot.targetDurationSec) : null,
      rpe: rpe,
      side: side,
    );

    return result.failureOrNull;
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
