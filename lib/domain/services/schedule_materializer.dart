import 'package:equatable/equatable.dart';

import '../entities/plan.dart';
import '../entities/scheduled_session.dart';
import '../enums/training_enums.dart';
import '../values/calendar_date.dart';
import '../values/schedule_pattern.dart';

/// A day the pattern says should exist, before it has an id or a database row.
class PlannedDay extends Equatable {
  const PlannedDay({
    required this.date,
    required this.weekNumber,
    required this.kind,
    this.sessionTemplateId,
    this.plannedDurationMin,
  });

  final CalendarDate date;
  final int weekNumber;
  final ScheduledSessionKind kind;
  final String? sessionTemplateId;
  final int? plannedDurationMin;

  @override
  List<Object?> get props => [
    date,
    weekNumber,
    kind,
    sessionTemplateId,
    plannedDurationMin,
  ];
}

/// What a re-commit should do to the calendar.
class ScheduleDiff extends Equatable {
  const ScheduleDiff({required this.toInsert, required this.toRemove});

  final List<PlannedDay> toInsert;

  /// Ids of rows the re-commit replaces. Only ever future, untouched days.
  final List<String> toRemove;

  bool get isEmpty => toInsert.isEmpty && toRemove.isEmpty;

  @override
  List<Object?> get props => [toInsert, toRemove];
}

/// Turns a program plus a repeating pattern into dated days (ADR §8.2).
///
/// Pure: no database, no clock of its own, no Flutter. Every input is an
/// argument, which is what makes the awkward cases — phase boundaries, a
/// re-commit halfway through a block — testable rather than hopeful.
abstract final class ScheduleMaterializer {
  /// Expands [program] into one [PlannedDay] per day it covers.
  ///
  /// **Weeks are counted from the start date, not from the calendar week.**
  /// Week 1 is the first seven days of the program, so a block beginning on a
  /// Wednesday runs Wed–Tue. Aligning to calendar weeks instead would make
  /// week 1 a stub of two or three days, and every adherence percentage
  /// computed against it a lie.
  static List<PlannedDay> plan({
    required Program program,
    required SchedulePattern pattern,
  }) {
    final weeks = program.weekCount;
    if (weeks <= 0 || program.phases.isEmpty) return const [];

    // Code → template, per phase. Built once rather than searched per day.
    final templatesByPhase = <String, Map<String, SessionTemplate>>{
      for (final phase in program.phases)
        phase.id: {for (final session in phase.sessions) session.code: session},
    };

    final days = <PlannedDay>[];

    for (var week = 1; week <= weeks; week++) {
      // A week outside every phase is a week the program does not plan — it
      // gets no rows at all, rather than a run of empty rest days that would
      // dilute adherence.
      final phase = program.phaseForWeek(week);
      if (phase == null) continue;

      for (var dayInWeek = 0; dayInWeek < 7; dayInWeek++) {
        final offset = (week - 1) * 7 + dayInWeek;
        final date = program.startDate.addDays(offset);

        final assignment = pattern.assignmentFor(
          dayOffset: offset,
          weekday: date.weekday,
        );

        final template = assignment.sessionCode == null
            ? null
            : templatesByPhase[phase.id]?[assignment.sessionCode];

        // The pattern asks for a Day C that this phase doesn't define. The
        // honest reading is that the phase simply doesn't train that day —
        // not that the user gets an untrainable gym day.
        final kind = assignment.isGym && template == null
            ? ScheduledSessionKind.rest
            : assignment.kind;

        days.add(
          PlannedDay(
            date: date,
            weekNumber: week,
            kind: kind,
            sessionTemplateId: template?.id,
            plannedDurationMin: template?.estimatedMinutes,
          ),
        );
      }
    }

    return days;
  }

  /// Works out what a re-commit may change.
  ///
  /// Two things are never rewritten (ADR §8.2):
  ///
  /// - **Anything before today.** A missed day stays missed and does not
  ///   cascade-shift; adherence has to tell the truth.
  /// - **Anything the user has touched** — started, finished, skipped, or
  ///   converted to a cricket day. Those are records, not plans.
  ///
  /// Everything else is replaced wholesale, which is simpler and safer than
  /// trying to edit rows in place: a day that already matches is dropped from
  /// both lists, so an unchanged pattern produces an empty diff.
  static ScheduleDiff diff({
    required List<ScheduledSession> existing,
    required List<PlannedDay> desired,
    required CalendarDate today,
  }) {
    final frozenDates = <CalendarDate>{};
    final replaceable = <ScheduledSession>[];

    for (final session in existing) {
      if (session.date.isBefore(today) || !session.isUntouched) {
        frozenDates.add(session.date);
      } else {
        replaceable.add(session);
      }
    }

    final wanted = desired
        .where((day) => !frozenDates.contains(day.date))
        .toList();

    // A day that already looks exactly as planned needs no write at all.
    final unchanged = <CalendarDate>{};
    final byDate = {for (final session in replaceable) session.date: session};

    for (final day in wanted) {
      final current = byDate[day.date];
      if (current == null) continue;

      if (current.kind == day.kind &&
          current.sessionTemplateId == day.sessionTemplateId &&
          current.weekNumber == day.weekNumber &&
          current.plannedDurationMin == day.plannedDurationMin) {
        unchanged.add(day.date);
      }
    }

    return ScheduleDiff(
      toInsert: wanted
          .where((day) => !unchanged.contains(day.date))
          .toList(growable: false),
      toRemove: replaceable
          .where((session) => !unchanged.contains(session.date))
          .map((session) => session.id)
          .toList(growable: false),
    );
  }
}
