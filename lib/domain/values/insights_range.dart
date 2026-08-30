import 'package:equatable/equatable.dart';

import '../entities/plan.dart';
import 'calendar_date.dart';

/// The Insights global filter (ADR §11.1).
///
/// `cycle` is a **phase** — the unit the plan already models — not a fixed
/// number of weeks. That is what makes "how did Cycle 2 go" answerable
/// without the user counting dates.
enum InsightsRangeKind { day, week, month, cycle, all }

/// An inclusive span of calendar days.
///
/// A null bound is unbounded, which is how `All` is expressed without
/// inventing a sentinel date. Everything downstream widens a null bound to the
/// storage format's extremes, so the SQL stays one shape.
class DateRange extends Equatable {
  const DateRange({this.start, this.end});

  /// Every day there has ever been — the `All` filter.
  static const unbounded = DateRange();

  final CalendarDate? start;
  final CalendarDate? end;

  bool get isUnbounded => start == null && end == null;

  /// Days covered, or null when either end is open.
  int? get dayCount {
    final from = start;
    final to = end;
    if (from == null || to == null) return null;
    return from.daysUntil(to) + 1;
  }

  bool contains(CalendarDate date) {
    if (start case final from? when date.isBefore(from)) return false;
    if (end case final to? when date.isAfter(to)) return false;
    return true;
  }

  @override
  List<Object?> get props => [start, end];

  @override
  String toString() => '${start ?? '…'}..${end ?? '…'}';
}

/// Turns a filter kind plus an anchor day into the window it means.
///
/// Pure functions over dates: the same anchor and the same locale always
/// produce the same window, which is what makes the range navigation
/// reversible and the whole thing testable without a database.
abstract final class InsightsWindow {
  static DateRange day(CalendarDate anchor) =>
      DateRange(start: anchor, end: anchor);

  /// The week containing [anchor].
  ///
  /// [firstWeekday] is ISO (1 = Monday … 7 = Sunday) and comes from the
  /// locale, never from a constant — which day a week starts on is locale
  /// data (ADR §12.2 rule 8).
  static DateRange week(CalendarDate anchor, {required int firstWeekday}) {
    final offset = (anchor.weekday - firstWeekday + 7) % 7;
    final start = anchor.addDays(-offset);
    return DateRange(start: start, end: start.addDays(6));
  }

  static DateRange month(CalendarDate anchor) {
    // Day zero of the next month is the last day of this one, which avoids a
    // leap-year table.
    final lastDay = DateTime(anchor.year, anchor.month + 1, 0).day;
    return DateRange(
      start: CalendarDate(anchor.year, anchor.month, 1),
      end: CalendarDate(anchor.year, anchor.month, lastDay),
    );
  }

  /// The days [phase] covers, derived from the program's start date.
  ///
  /// Phase weeks are 1-based and inclusive, so week 1 begins on the start date
  /// itself and week `endWeek` ends six days after it begins.
  static DateRange phase(Program program, Phase phase) {
    final start = program.startDate.addDays((phase.startWeek - 1) * 7);
    return DateRange(start: start, end: start.addDays(phase.weekCount * 7 - 1));
  }

  /// The phase [anchor] falls in, or null when it falls outside the program.
  static Phase? phaseAt(Program? program, CalendarDate anchor) {
    if (program == null) return null;
    final week = program.weekOf(anchor);
    if (week == null) return null;
    return program.phaseForWeek(week);
  }

  /// The nearest day inside [program] to [anchor].
  ///
  /// Switching to the Cycle filter from a day outside the program would
  /// otherwise resolve to nothing; clamping lands on the first or last phase
  /// instead, which is the cycle the user can actually mean.
  static CalendarDate clampToProgram(Program program, CalendarDate anchor) {
    final phases = program.phases;
    if (phases.isEmpty) return anchor;

    final first = phase(program, phases.first);
    final last = phase(program, phases.last);

    if (first.start case final from? when anchor.isBefore(from)) return from;
    if (last.end case final to? when anchor.isAfter(to)) return to;
    return anchor;
  }
}
