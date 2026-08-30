import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../../core/error/failure.dart';
import '../../../../domain/entities/plan.dart';
import '../../../../domain/entities/scheduled_session.dart';
import '../../../../domain/entities/session_log.dart';
import '../../../../domain/entities/check_in.dart';
import '../../../../domain/repositories/check_in_repository.dart';
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

    /// A training cycle has ended with no weigh-in recorded inside it, so the
    /// screen asks for one. False whenever anything is missing rather than
    /// nagging on incomplete information.
    @Default(false) bool checkInDue,
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
    required CheckInRepository checkInRepository,
    DateTime Function()? now,
  }) : _plan = planRepository,
       _schedule = scheduleRepository,
       _log = logRepository,
       _checkIns = checkInRepository,
       _now = now ?? DateTime.now,
       super(const TodayLoading()) {
    _programSubscription = _plan.watchActiveProgram().listen((program) {
      _program = program;
      _programLoaded = true;
      _emit();
    }, onError: _onError);

    final today = CalendarDate.from(_now());
    _weekSubscription = _schedule
        .watchActiveRange(from: today.addDays(-3), to: today.addDays(3))
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

    _checkInSubscription = _checkIns.watchLatestWeight().listen((checkIn) {
      _latestCheckIn = checkIn;
      _emit();
    }, onError: _onError);
  }

  final PlanRepository _plan;
  final ScheduleRepository _schedule;
  final LogRepository _log;
  final CheckInRepository _checkIns;
  final DateTime Function() _now;

  late final StreamSubscription<void> _programSubscription;
  late final StreamSubscription<void> _weekSubscription;
  late final StreamSubscription<void> _sessionSubscription;
  late final StreamSubscription<void> _checkInSubscription;

  Program? _program;
  List<ScheduledSession> _week = const [];
  SessionLog? _activeSession;
  SessionLog? _lastSession;
  SessionTemplate? _template;
  CheckIn? _latestCheckIn;

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

  /// Whether a cycle has ended without a weigh-in inside it.
  ///
  /// "Cycle" is a **phase**, which is the unit the plan already models and the
  /// one `checkInDueAtEnd` was put on the table for (ADR §10.1). The prompt
  /// fires once per phase: recording a weight lands it inside the current
  /// phase's window, which is exactly the condition being tested, so the card
  /// disappears on its own rather than needing a dismissed flag.
  ///
  /// Everything unknown means "not due". A prompt raised on missing data is a
  /// nag, and this one asks the user to go and stand on a scale.
  bool get _isCheckInDue {
    final program = _program;
    if (program == null) return false;

    final week = program.weekOf(_today);
    if (week == null) return false;

    final phase = program.phaseForWeek(week);
    if (phase == null || !phase.checkInDueAtEnd) return false;

    // Only once the phase is actually over — mid-block is not a cycle end.
    if (week < phase.endWeek) return false;

    final phaseStart = program.startDate.addDays((phase.startWeek - 1) * 7);
    final latest = _latestCheckIn?.date;

    // Never weighed, or last weighed before this phase began.
    return latest == null || latest.isBefore(phaseStart);
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
        checkInDue: _isCheckInDue,
      ),
    );
  }

  @override
  Future<void> close() {
    _programSubscription.cancel();
    _weekSubscription.cancel();
    _sessionSubscription.cancel();
    _checkInSubscription.cancel();
    return super.close();
  }
}
