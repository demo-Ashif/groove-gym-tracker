import 'package:flutter_test/flutter_test.dart';
import 'package:groove/domain/entities/plan.dart';
import 'package:groove/domain/entities/scheduled_session.dart';
import 'package:groove/domain/enums/training_enums.dart';
import 'package:groove/domain/services/schedule_materializer.dart';
import 'package:groove/domain/values/calendar_date.dart';
import 'package:groove/domain/values/schedule_pattern.dart';

/// The materializer is where a plan becomes dates, and dates are where
/// off-by-ones hide. Everything here is pure, so every awkward case — phase
/// boundaries, a re-commit mid-block, a code a phase doesn't define — is
/// reachable without a database.
void main() {
  // A Sunday, matching the ADR's example week (Sun–Thu gym, Fri rest, Sat
  // cricket).
  const start = CalendarDate(2026, 8, 16);

  SessionTemplate session(String code, {int? minutes}) => SessionTemplate(
    id: 'session-$code',
    phaseId: 'phase-1',
    code: code,
    title: 'Day $code',
    orderIndex: 0,
    estimatedMinutes: minutes,
  );

  Program program({
    required List<Phase> phases,
    CalendarDate startDate = start,
  }) => Program(
    id: 'program-1',
    name: 'Block',
    startDate: startDate,
    phases: phases,
  );

  Phase phase({
    required String id,
    required int startWeek,
    required int endWeek,
    List<SessionTemplate> sessions = const [],
  }) => Phase(
    id: id,
    programId: 'program-1',
    name: 'Cycle',
    orderIndex: 0,
    startWeek: startWeek,
    endWeek: endWeek,
    sessions: sessions,
  );

  group('weekly pattern', () {
    final weekly = SchedulePattern.weekly({
      DateTime.sunday: const DayAssignment.gym('A'),
      DateTime.monday: const DayAssignment.gym('B'),
      DateTime.friday: const DayAssignment.rest(),
      DateTime.saturday: const DayAssignment.cricket(),
    });

    test('materializes seven days per covered week', () {
      final days = ScheduleMaterializer.plan(
        program: program(
          phases: [
            phase(
              id: 'phase-1',
              startWeek: 1,
              endWeek: 2,
              sessions: [session('A'), session('B')],
            ),
          ],
        ),
        pattern: weekly,
      );

      expect(days, hasLength(14));
      expect(days.first.date, start);
      expect(days.last.date, start.addDays(13));
      expect(days.where((d) => d.weekNumber == 1), hasLength(7));
      expect(days.where((d) => d.weekNumber == 2), hasLength(7));
    });

    test('weeks run from the start date, not from the calendar week', () {
      // Starting on a Wednesday: week 1 must be Wed–Tue, or week 1 is a stub
      // and every adherence percentage computed against it is a lie.
      const wednesday = CalendarDate(2026, 8, 19);

      final days = ScheduleMaterializer.plan(
        program: program(
          startDate: wednesday,
          phases: [
            phase(
              id: 'phase-1',
              startWeek: 1,
              endWeek: 1,
              sessions: [session('A')],
            ),
          ],
        ),
        pattern: weekly,
      );

      expect(days, hasLength(7));
      expect(days.first.date, wednesday);
      expect(days.last.date, const CalendarDate(2026, 8, 25));
      // Each weekday appears exactly once in the window.
      expect(days.map((d) => d.date.weekday).toSet(), hasLength(7));
    });

    test('assigns the right kind to each weekday', () {
      final days = ScheduleMaterializer.plan(
        program: program(
          phases: [
            phase(
              id: 'phase-1',
              startWeek: 1,
              endWeek: 1,
              sessions: [session('A', minutes: 90), session('B')],
            ),
          ],
        ),
        pattern: weekly,
      );

      final byWeekday = {for (final day in days) day.date.weekday: day};

      expect(byWeekday[DateTime.sunday]!.kind, ScheduledSessionKind.gym);
      expect(byWeekday[DateTime.sunday]!.sessionTemplateId, 'session-A');
      expect(byWeekday[DateTime.sunday]!.plannedDurationMin, 90);

      expect(byWeekday[DateTime.saturday]!.kind, ScheduledSessionKind.cricket);
      expect(byWeekday[DateTime.saturday]!.sessionTemplateId, isNull);

      // Friday is explicitly rest; Tuesday is absent from the map, which means
      // the same thing.
      expect(byWeekday[DateTime.friday]!.kind, ScheduledSessionKind.rest);
      expect(byWeekday[DateTime.tuesday]!.kind, ScheduledSessionKind.rest);
    });

    test('resolves a session code inside the phase covering that week', () {
      // The reason assignments carry a code and not a template id: each phase
      // has its own Day A.
      final days = ScheduleMaterializer.plan(
        program: program(
          phases: [
            phase(
              id: 'phase-1',
              startWeek: 1,
              endWeek: 1,
              sessions: [session('A')],
            ),
            Phase(
              id: 'phase-2',
              programId: 'program-1',
              name: 'Cycle 2',
              orderIndex: 1,
              startWeek: 2,
              endWeek: 2,
              sessions: const [
                SessionTemplate(
                  id: 'session-A-phase-2',
                  phaseId: 'phase-2',
                  code: 'A',
                  title: 'Day A',
                  orderIndex: 0,
                ),
              ],
            ),
          ],
        ),
        pattern: weekly,
      );

      final sundays = days
          .where((d) => d.date.weekday == DateTime.sunday)
          .toList();

      expect(sundays, hasLength(2));
      expect(sundays.first.sessionTemplateId, 'session-A');
      expect(sundays.last.sessionTemplateId, 'session-A-phase-2');
    });

    test('a code the phase does not define becomes a rest day', () {
      // The phase simply doesn't train that day. An untrainable gym day would
      // be worse than an honest rest day.
      final days = ScheduleMaterializer.plan(
        program: program(
          phases: [
            phase(
              id: 'phase-1',
              startWeek: 1,
              endWeek: 1,
              sessions: [session('A')],
            ),
          ],
        ),
        pattern: weekly,
      );

      final monday = days.firstWhere((d) => d.date.weekday == DateTime.monday);

      expect(monday.kind, ScheduledSessionKind.rest);
      expect(monday.sessionTemplateId, isNull);
    });

    test('a week no phase covers gets no rows at all', () {
      final days = ScheduleMaterializer.plan(
        program: Program(
          id: 'program-1',
          name: 'Block',
          startDate: start,
          phases: [
            phase(
              id: 'phase-1',
              startWeek: 1,
              endWeek: 1,
              sessions: [session('A')],
            ),
            // Week 2 is a hole; weeks run to 3.
            phase(
              id: 'phase-3',
              startWeek: 3,
              endWeek: 3,
              sessions: [session('A')],
            ),
          ],
        ),
        pattern: weekly,
      );

      expect(days.map((d) => d.weekNumber).toSet(), {1, 3});
      // Empty rest days for an unplanned week would dilute adherence.
      expect(days, hasLength(14));
    });

    test('a program with no phases materializes nothing', () {
      expect(
        ScheduleMaterializer.plan(
          program: program(phases: const []),
          pattern: weekly,
        ),
        isEmpty,
      );
    });
  });

  group('cycle pattern', () {
    test('rotates from the start date and drifts across the calendar week', () {
      // Three on, one off.
      final cycle = SchedulePattern.cycle(const [
        DayAssignment.gym('A'),
        DayAssignment.gym('B'),
        DayAssignment.gym('C'),
        DayAssignment.rest(),
      ]);

      final days = ScheduleMaterializer.plan(
        program: program(
          phases: [
            phase(
              id: 'phase-1',
              startWeek: 1,
              endWeek: 2,
              sessions: [session('A'), session('B'), session('C')],
            ),
          ],
        ),
        pattern: cycle,
      );

      expect(days.map((d) => d.kind).take(5), [
        ScheduledSessionKind.gym,
        ScheduledSessionKind.gym,
        ScheduledSessionKind.gym,
        ScheduledSessionKind.rest,
        ScheduledSessionKind.gym,
      ]);

      // Day 8 is offset 7, which is 7 % 4 = 3 — the rest day, on a different
      // weekday than the first one. Drifting is the point of a cycle.
      expect(days[7].kind, ScheduledSessionKind.rest);
      expect(days[7].date.weekday, isNot(days[3].date.weekday));
    });

    test('an empty cycle is all rest rather than a crash', () {
      final days = ScheduleMaterializer.plan(
        program: program(
          phases: [phase(id: 'phase-1', startWeek: 1, endWeek: 1)],
        ),
        pattern: const SchedulePattern.cycle([]),
      );

      expect(days, hasLength(7));
      expect(days.every((d) => d.kind == ScheduledSessionKind.rest), isTrue);
    });
  });

  group('diff', () {
    const today = CalendarDate(2026, 8, 20);

    ScheduledSession existing(
      CalendarDate date, {
      ScheduledSessionStatus status = ScheduledSessionStatus.upcoming,
      ScheduledSessionKind kind = ScheduledSessionKind.gym,
      String? templateId = 'session-A',
      int weekNumber = 1,
    }) => ScheduledSession(
      id: 'row-${date.toIso()}',
      programId: 'program-1',
      date: date,
      weekNumber: weekNumber,
      kind: kind,
      sessionTemplateId: templateId,
      status: status,
    );

    PlannedDay planned(
      CalendarDate date, {
      ScheduledSessionKind kind = ScheduledSessionKind.gym,
      String? templateId = 'session-A',
      int weekNumber = 1,
    }) => PlannedDay(
      date: date,
      weekNumber: weekNumber,
      kind: kind,
      sessionTemplateId: templateId,
    );

    test('an unchanged plan produces no writes', () {
      final diff = ScheduleMaterializer.diff(
        existing: [existing(today), existing(today.addDays(1))],
        desired: [planned(today), planned(today.addDays(1))],
        today: today,
      );

      expect(diff.isEmpty, isTrue);
    });

    test('never rewrites a day before today', () {
      final yesterday = today.addDays(-1);

      final diff = ScheduleMaterializer.diff(
        existing: [existing(yesterday)],
        // The pattern now says yesterday should have been a rest day.
        desired: [planned(yesterday, kind: ScheduledSessionKind.rest)],
        today: today,
      );

      // A missed day stays missed and does not cascade-shift (ADR §8.2).
      expect(diff.isEmpty, isTrue);
    });

    test('never rewrites a day the user has touched', () {
      for (final status in [
        ScheduledSessionStatus.completed,
        ScheduledSessionStatus.inProgress,
        ScheduledSessionStatus.partial,
        ScheduledSessionStatus.skipped,
      ]) {
        final diff = ScheduleMaterializer.diff(
          existing: [existing(today, status: status)],
          desired: [planned(today, kind: ScheduledSessionKind.rest)],
          today: today,
        );

        expect(diff.isEmpty, isTrue, reason: status.name);
      }
    });

    test('replaces a future untouched day whose prescription changed', () {
      final tomorrow = today.addDays(1);

      final diff = ScheduleMaterializer.diff(
        existing: [existing(tomorrow)],
        desired: [planned(tomorrow, templateId: 'session-B')],
        today: today,
      );

      expect(diff.toRemove, ['row-${tomorrow.toIso()}']);
      expect(diff.toInsert.single.sessionTemplateId, 'session-B');
    });

    test('drops a day the new pattern no longer wants', () {
      final tomorrow = today.addDays(1);

      final diff = ScheduleMaterializer.diff(
        existing: [existing(tomorrow)],
        desired: const [],
        today: today,
      );

      expect(diff.toRemove, ['row-${tomorrow.toIso()}']);
      expect(diff.toInsert, isEmpty);
    });

    test('inserts a day the calendar does not have yet', () {
      final tomorrow = today.addDays(1);

      final diff = ScheduleMaterializer.diff(
        existing: const [],
        desired: [planned(tomorrow)],
        today: today,
      );

      expect(diff.toInsert.single.date, tomorrow);
      expect(diff.toRemove, isEmpty);
    });

    test('leaves a frozen date alone even when the plan wants it back', () {
      // The user skipped today; the re-commit must not resurrect it as an
      // upcoming gym day.
      final diff = ScheduleMaterializer.diff(
        existing: [existing(today, status: ScheduledSessionStatus.skipped)],
        desired: [planned(today)],
        today: today,
      );

      expect(diff.isEmpty, isTrue);
    });

    test('today itself is editable while it is still untouched', () {
      // "Before today" is strict: the day you are standing in can still be
      // re-planned right up until you start it.
      final diff = ScheduleMaterializer.diff(
        existing: [existing(today)],
        desired: [
          planned(today, kind: ScheduledSessionKind.cricket, templateId: null),
        ],
        today: today,
      );

      expect(diff.toRemove, hasLength(1));
      expect(diff.toInsert.single.kind, ScheduledSessionKind.cricket);
    });
  });
}
