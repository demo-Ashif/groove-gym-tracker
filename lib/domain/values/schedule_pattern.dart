import 'package:equatable/equatable.dart';

import '../enums/training_enums.dart';

/// What a single day in a repeating pattern is for.
///
/// A gym day names a session **code** ("A"), not a template id. That is the
/// load-bearing detail: each phase has its own Day A, so an assignment that
/// pointed at a template id would keep sending week 5 to phase 1's session.
/// The materializer resolves the code inside whichever phase covers the week.
class DayAssignment extends Equatable {
  const DayAssignment.gym(String this.sessionCode)
    : kind = ScheduledSessionKind.gym;

  const DayAssignment.rest()
    : kind = ScheduledSessionKind.rest,
      sessionCode = null;

  /// Cricket overrides gym as a first-class kind, so a light week reads as
  /// intentional rather than as a gap (ADR §8.2).
  const DayAssignment.cricket()
    : kind = ScheduledSessionKind.cricket,
      sessionCode = null;

  const DayAssignment.custom()
    : kind = ScheduledSessionKind.custom,
      sessionCode = null;

  final ScheduledSessionKind kind;

  /// Set only for [ScheduledSessionKind.gym].
  final String? sessionCode;

  bool get isGym => kind == ScheduledSessionKind.gym;

  @override
  List<Object?> get props => [kind, sessionCode];
}

/// How a program repeats (ADR §8.1).
///
/// Sealed, so adding a cadence is a compile error at every consumer rather
/// than a silently unhandled case that materializes an empty calendar.
sealed class SchedulePattern extends Equatable {
  const SchedulePattern();

  /// A repeating day-of-week pattern — Sun–Thu gym, Fri rest, Sat cricket.
  /// Weekdays absent from [days] are rest days.
  const factory SchedulePattern.weekly(Map<int, DayAssignment> days) =
      WeeklyPattern;

  /// "N days on, M days off", rotating from the program's start date.
  const factory SchedulePattern.cycle(List<DayAssignment> days) = CyclePattern;

  /// The assignment for a given day, where [dayOffset] is days elapsed since
  /// the program's start date and [weekday] is its ISO-8601 weekday.
  DayAssignment assignmentFor({required int dayOffset, required int weekday});

  /// Session codes the pattern refers to. The editor uses this to warn when a
  /// phase has no matching template.
  Set<String> get referencedCodes;
}

final class WeeklyPattern extends SchedulePattern {
  const WeeklyPattern(this.days);

  /// Keyed by ISO-8601 weekday, 1 = Monday … 7 = Sunday. Which day a *week*
  /// starts on is locale data and belongs to the UI, never to this map
  /// (ADR §12.2 rule 8).
  final Map<int, DayAssignment> days;

  @override
  DayAssignment assignmentFor({required int dayOffset, required int weekday}) =>
      days[weekday] ?? const DayAssignment.rest();

  @override
  Set<String> get referencedCodes => {
    for (final assignment in days.values) ?assignment.sessionCode,
  };

  @override
  List<Object?> get props => [days];
}

final class CyclePattern extends SchedulePattern {
  const CyclePattern(this.days);

  /// One entry per day of the rotation, repeating from the start date. A
  /// "3 on, 1 off" block is four entries.
  final List<DayAssignment> days;

  @override
  DayAssignment assignmentFor({required int dayOffset, required int weekday}) {
    if (days.isEmpty) return const DayAssignment.rest();
    // Modulo on the offset, not on the weekday: a cycle deliberately drifts
    // across the calendar week, which is the whole point of it.
    return days[dayOffset % days.length];
  }

  @override
  Set<String> get referencedCodes => {
    for (final assignment in days) ?assignment.sessionCode,
  };

  @override
  List<Object?> get props => [days];
}
