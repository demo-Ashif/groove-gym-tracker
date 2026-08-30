import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../../domain/entities/plan.dart';
import '../../../../domain/repositories/plan_repository.dart';
import '../../../../domain/values/calendar_date.dart';
import '../../../../domain/values/insights_range.dart';

part 'insights_range_cubit.freezed.dart';

/// The Insights global filter (ADR §11.1).
///
/// Holds the *intent* — which kind of window, anchored where — and derives the
/// actual [range] from it, rather than storing a resolved range that would go
/// stale the moment the program or the locale changed.
@freezed
abstract class InsightsRangeState with _$InsightsRangeState {
  const InsightsRangeState._();

  const factory InsightsRangeState({
    /// A day inside the current window. Navigation moves this, not the range.
    required CalendarDate anchor,

    required CalendarDate today,

    @Default(InsightsRangeKind.week) InsightsRangeKind kind,

    /// The active program, for resolving cycles. Null when none is running,
    /// which is also what hides the Cycle filter.
    Program? program,

    /// ISO weekday the user's locale starts a week on. Never assumed — which
    /// day a week starts on is locale data (ADR §12.2 rule 8).
    @Default(DateTime.monday) int firstWeekday,
  }) = _InsightsRangeState;

  /// The phase the anchor sits in, when the filter is showing a cycle.
  Phase? get phase => kind == InsightsRangeKind.cycle
      ? InsightsWindow.phaseAt(program, anchor)
      : null;

  /// The window every card queries.
  DateRange get range => switch (kind) {
    InsightsRangeKind.day => InsightsWindow.day(anchor),
    InsightsRangeKind.week => InsightsWindow.week(
      anchor,
      firstWeekday: firstWeekday,
    ),
    InsightsRangeKind.month => InsightsWindow.month(anchor),
    // A cycle with no phase behind it can only happen in the frame between a
    // program being deleted and the subscription reporting it; the month is a
    // truthful window to sit in until then.
    InsightsRangeKind.cycle => switch ((program, phase)) {
      (final Program program, final Phase phase) => InsightsWindow.phase(
        program,
        phase,
      ),
      _ => InsightsWindow.month(anchor),
    },
    InsightsRangeKind.all => DateRange.unbounded,
  };

  /// Cycle is offered only when there is a program with phases to cycle
  /// through — a filter that resolves to nothing is worse than no filter.
  bool get offersCycle => program?.phases.isNotEmpty ?? false;

  List<InsightsRangeKind> get availableKinds => [
    for (final kind in InsightsRangeKind.values)
      if (kind != InsightsRangeKind.cycle || offersCycle) kind,
  ];

  bool get canGoBack => switch (kind) {
    InsightsRangeKind.all => false,
    InsightsRangeKind.cycle => _adjacentPhase(-1) != null,
    _ => true,
  };

  /// Forward stops at today: there is nothing to plot in the future, and an
  /// arrow that walks into empty months reads as a broken chart.
  bool get canGoForward => switch (kind) {
    InsightsRangeKind.all => false,
    InsightsRangeKind.cycle => _adjacentPhase(1) != null,
    _ => range.end?.isBefore(today) ?? false,
  };

  /// The phase [offset] positions from the current one, or null at either end.
  Phase? _adjacentPhase(int offset) {
    final program = this.program;
    final current = phase;
    if (program == null || current == null) return null;

    final index = program.phases.indexOf(current) + offset;
    if (index < 0 || index >= program.phases.length) return null;
    return program.phases[index];
  }

  /// Where the anchor lands after stepping [offset] windows.
  CalendarDate? anchorAfter(int offset) {
    switch (kind) {
      case InsightsRangeKind.all:
        return null;
      case InsightsRangeKind.day:
        return anchor.addDays(offset);
      case InsightsRangeKind.week:
        return anchor.addDays(offset * 7);
      case InsightsRangeKind.month:
        // Day 1 first: stepping from the 31st would otherwise skip February.
        final moved = DateTime(anchor.year, anchor.month + offset);
        return CalendarDate(moved.year, moved.month, 1);
      case InsightsRangeKind.cycle:
        final program = this.program;
        final target = _adjacentPhase(offset);
        if (program == null || target == null) return null;
        return InsightsWindow.phase(program, target).start;
    }
  }
}

/// One filter for the whole tab.
///
/// App-scoped rather than screen-scoped: switching to Today and back must not
/// silently reset the range the user chose, and the cost of keeping it is one
/// subscription to the active program.
class InsightsRangeCubit extends Cubit<InsightsRangeState> {
  InsightsRangeCubit({
    required PlanRepository planRepository,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now,
       super(
         InsightsRangeState(
           anchor: CalendarDate.from((now ?? DateTime.now)()),
           today: CalendarDate.from((now ?? DateTime.now)()),
         ),
       ) {
    _programSubscription = planRepository.watchActiveProgram().listen((
      program,
    ) {
      final wasOfferingCycle = state.offersCycle;
      var next = state.copyWith(program: program, today: _today);

      // The program that made Cycle selectable is gone — fall back rather than
      // leave the filter pointing at a window that no longer exists.
      if (state.kind == InsightsRangeKind.cycle && !next.offersCycle) {
        next = next.copyWith(kind: InsightsRangeKind.month);
      } else if (state.kind == InsightsRangeKind.cycle &&
          !wasOfferingCycle &&
          program != null) {
        next = next.copyWith(
          anchor: InsightsWindow.clampToProgram(program, next.anchor),
        );
      }

      emit(next);
    }, onError: _onProgramError);
  }

  final DateTime Function() _now;
  late final StreamSubscription<Program?> _programSubscription;

  CalendarDate get _today => CalendarDate.from(_now());

  /// A failed program read is not worth an error screen over the whole tab —
  /// the filter degrades to the non-cycle windows, which need no program.
  void _onProgramError(Object _) {
    if (isClosed) return;
    emit(state.copyWith(program: null, today: _today));
  }

  /// Locale data, pushed in from the widget tree — the domain must not guess
  /// which day a week starts on.
  void setFirstDayOfWeek(int isoWeekday) {
    if (state.firstWeekday == isoWeekday) return;
    emit(state.copyWith(firstWeekday: isoWeekday, today: _today));
  }

  void selectKind(InsightsRangeKind kind) {
    if (state.kind == kind) return;

    // Re-anchor on today whenever the shape of the window changes: keeping a
    // three-month-old anchor and switching from All to Day drops the user
    // somewhere they did not ask to be.
    var anchor = _today;
    final program = state.program;
    if (kind == InsightsRangeKind.cycle && program != null) {
      anchor = InsightsWindow.clampToProgram(program, anchor);
    }

    emit(state.copyWith(kind: kind, anchor: anchor, today: _today));
  }

  void previous() => _step(-1);

  void next() => _step(1);

  void _step(int offset) {
    if (offset < 0 && !state.canGoBack) return;
    if (offset > 0 && !state.canGoForward) return;

    final anchor = state.anchorAfter(offset);
    if (anchor == null) return;

    emit(state.copyWith(anchor: anchor, today: _today));
  }

  @override
  Future<void> close() {
    _programSubscription.cancel();
    return super.close();
  }
}
