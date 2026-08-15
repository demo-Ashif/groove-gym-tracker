import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../../core/error/failure.dart';
import '../../../../domain/entities/plan.dart';
import '../../../../domain/entities/scheduled_session.dart';
import '../../../../domain/entities/session_log.dart';
import '../../../../domain/repositories/log_repository.dart';
import '../../../../domain/repositories/plan_repository.dart';
import '../../../../domain/repositories/schedule_repository.dart';
import '../../../../domain/values/calendar_date.dart';

part 'today_cubit.freezed.dart';

@freezed
sealed class TodayState with _$TodayState {
  const TodayState._();

  const factory TodayState.loading() = TodayLoading;

  const factory TodayState.data({
    /// Null when no program is active.
    Program? program,

    /// Today's row, if the calendar has one.
    ScheduledSession? today,

    /// The seven days around today, for the strip.
    @Default([]) List<ScheduledSession> week,

    /// The template behind today's session, when it is a gym day.
    SessionTemplate? template,

    /// A session already running — the Today card offers to resume rather than
    /// to start.
    SessionLog? activeSession,

    /// The last finished session, for the recap.
    SessionLog? lastSession,
  }) = TodayData;

  const factory TodayState.failure(Failure failure) = TodayFailure;
}

/// The screen the app exists to show (ADR §9.1).
///
/// Everything here is derived from the calendar rather than recomputed from a
/// recurrence rule, which is the payoff for materializing the schedule.
class TodayCubit extends Cubit<TodayState> {
  TodayCubit({
    required PlanRepository planRepository,
    required ScheduleRepository scheduleRepository,
    required LogRepository logRepository,
    DateTime Function()? now,
  }) : _plan = planRepository,
       _schedule = scheduleRepository,
       _log = logRepository,
       _now = now ?? DateTime.now,
       super(const TodayLoading()) {
    _programSubscription = _plan.watchActiveProgram().listen((program) {
      _program = program;
      _programLoaded = true;
      _emit();
    }, onError: _onError);

    final today = CalendarDate.from(_now());
    _weekSubscription = _schedule
        .watchRange(from: today.addDays(-3), to: today.addDays(3))
        .listen((days) {
          _week = days;
          _weekLoaded = true;
          unawaited(_resolveToday());
          _emit();
        }, onError: _onError);

    _sessionSubscription = _log.watchActiveSession().listen((session) {
      _activeSession = session;
      _emit();
    }, onError: _onError);
  }

  final PlanRepository _plan;
  final ScheduleRepository _schedule;
  final LogRepository _log;
  final DateTime Function() _now;

  late final StreamSubscription<void> _programSubscription;
  late final StreamSubscription<void> _weekSubscription;
  late final StreamSubscription<void> _sessionSubscription;

  Program? _program;
  List<ScheduledSession> _week = const [];
  SessionLog? _activeSession;
  SessionLog? _lastSession;
  SessionTemplate? _template;

  bool _programLoaded = false;
  bool _weekLoaded = false;

  void _onError(Object error) =>
      emit(TodayState.failure(Failure.fromException(error)));

  CalendarDate get _today => CalendarDate.from(_now());

  ScheduledSession? get _todayRow {
    for (final day in _week) {
      if (day.date == _today) return day;
    }
    return null;
  }

  /// Resolves today's template and the previous session's recap.
  Future<void> _resolveToday() async {
    final today = _todayRow;

    _template = null;
    if (today?.sessionTemplateId case final templateId?) {
      _template = _program?.phases
          .expand((phase) => phase.sessions)
          .where((session) => session.id == templateId)
          .firstOrNull;
    }

    if (today != null) {
      _lastSession = (await _log.latestForScheduled(today.id)).dataOrNull;
    }

    if (!isClosed) _emit();
  }

  void _emit() {
    if (!_programLoaded || !_weekLoaded) return;

    emit(
      TodayState.data(
        program: _program,
        today: _todayRow,
        week: _week,
        template: _template,
        activeSession: _activeSession,
        lastSession: _lastSession,
      ),
    );
  }

  @override
  Future<void> close() {
    _programSubscription.cancel();
    _weekSubscription.cancel();
    _sessionSubscription.cancel();
    return super.close();
  }
}
