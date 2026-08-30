import 'package:flutter_test/flutter_test.dart';
import 'package:groove/domain/entities/insights.dart';
import 'package:groove/domain/entities/plan.dart';
import 'package:groove/domain/services/trend_service.dart';
import 'package:groove/domain/values/calendar_date.dart';
import 'package:groove/domain/values/insights_range.dart';

Program programWithPhases() {
  const start = CalendarDate(2026, 8, 17); // A Monday.
  return Program(
    id: 'p',
    name: 'Block',
    startDate: start,
    isActive: true,
    phases: const [
      Phase(
        id: 'a',
        programId: 'p',
        name: 'Cycle 1',
        orderIndex: 0,
        startWeek: 1,
        endWeek: 3,
      ),
      Phase(
        id: 'b',
        programId: 'p',
        name: 'Cycle 2',
        orderIndex: 1,
        startWeek: 4,
        endWeek: 6,
      ),
    ],
  );
}

void main() {
  group('windows', () {
    test('a day is itself', () {
      const day = CalendarDate(2026, 8, 20);
      final range = InsightsWindow.day(day);

      expect(range.start, day);
      expect(range.end, day);
      expect(range.dayCount, 1);
    });

    test('a week starts on the locale first day, not on Monday', () {
      const thursday = CalendarDate(2026, 8, 20);

      final isoWeek = InsightsWindow.week(
        thursday,
        firstWeekday: DateTime.monday,
      );
      expect(isoWeek.start, const CalendarDate(2026, 8, 17));
      expect(isoWeek.end, const CalendarDate(2026, 8, 23));

      // A US locale starts the same day's week three days earlier.
      final usWeek = InsightsWindow.week(
        thursday,
        firstWeekday: DateTime.sunday,
      );
      expect(usWeek.start, const CalendarDate(2026, 8, 16));
      expect(usWeek.end, const CalendarDate(2026, 8, 22));
      expect(usWeek.dayCount, 7);
    });

    test('a month covers its real length, February included', () {
      final february = InsightsWindow.month(const CalendarDate(2028, 2, 14));

      expect(february.start, const CalendarDate(2028, 2, 1));
      // 2028 is a leap year — the classic off-by-one in a hand-rolled table.
      expect(february.end, const CalendarDate(2028, 2, 29));
    });

    test('a phase spans whole weeks from the program start', () {
      final program = programWithPhases();

      final first = InsightsWindow.phase(program, program.phases.first);
      expect(first.start, const CalendarDate(2026, 8, 17));
      expect(first.end, const CalendarDate(2026, 9, 6));
      expect(first.dayCount, 21);

      final second = InsightsWindow.phase(program, program.phases.last);
      expect(second.start, const CalendarDate(2026, 9, 7));
      expect(second.dayCount, 21);
    });

    test('the phase at a date is the one containing it', () {
      final program = programWithPhases();

      expect(
        InsightsWindow.phaseAt(program, const CalendarDate(2026, 9, 8))?.name,
        'Cycle 2',
      );
      // Before the program starts there is no phase to be in.
      expect(
        InsightsWindow.phaseAt(program, const CalendarDate(2026, 8, 1)),
        isNull,
      );
      expect(InsightsWindow.phaseAt(null, const CalendarDate(2026, 9, 8)), isNull);
    });

    test('clamping lands an outside date on the nearest end of the program', () {
      final program = programWithPhases();

      expect(
        InsightsWindow.clampToProgram(program, const CalendarDate(2026, 1, 1)),
        const CalendarDate(2026, 8, 17),
      );
      expect(
        InsightsWindow.clampToProgram(program, const CalendarDate(2027, 1, 1)),
        const CalendarDate(2026, 9, 27),
      );
      // A date inside is left alone.
      expect(
        InsightsWindow.clampToProgram(program, const CalendarDate(2026, 9, 1)),
        const CalendarDate(2026, 9, 1),
      );
    });

    test('an unbounded range contains everything', () {
      expect(DateRange.unbounded.contains(const CalendarDate(1999, 1, 1)), isTrue);
      expect(DateRange.unbounded.dayCount, isNull);
      expect(DateRange.unbounded.isUnbounded, isTrue);
    });
  });

  group('moving average', () {
    WeightPoint at(int day, double kg) =>
        WeightPoint(date: CalendarDate(2026, 8, day), kg: kg);

    test('averages over calendar days, not over the last N entries', () {
      final points = TrendService.withMovingAverage([
        at(1, 84),
        at(2, 82),
        // Ten days later: both earlier points have aged out of the window.
        at(12, 80),
      ]);

      expect(points[0].averageKg, closeTo(84, 0.0001));
      expect(points[1].averageKg, closeTo(83, 0.0001));
      expect(points[2].averageKg, closeTo(80, 0.0001));
    });

    test('keeps points inside the window', () {
      final points = TrendService.withMovingAverage([
        at(1, 84),
        at(7, 82), // Day 7 is still within a 7-day trailing window of day 1.
      ]);

      expect(points.last.averageKg, closeTo(83, 0.0001));
    });

    test('is safe on an empty series and on one point', () {
      expect(TrendService.withMovingAverage(const []), isEmpty);
      expect(TrendService.change(const []), isNull);

      final single = TrendService.withMovingAverage([at(1, 84)]);
      expect(single.single.averageKg, 84);
      expect(TrendService.change(single), isNull);
    });

    test('change is newest minus oldest', () {
      final points = TrendService.withMovingAverage([at(1, 84), at(20, 81.5)]);
      expect(TrendService.change(points), closeTo(-2.5, 0.0001));
    });
  });
}
