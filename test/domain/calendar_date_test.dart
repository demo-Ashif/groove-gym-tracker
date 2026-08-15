import 'package:flutter_test/flutter_test.dart';
import 'package:groove/data/mappers/progression_rule_codec.dart';
import 'package:groove/domain/values/calendar_date.dart';
import 'package:groove/domain/values/progression_rule.dart';

void main() {
  group('CalendarDate', () {
    test('round-trips the storage format', () {
      const date = CalendarDate(2026, 8, 16);

      expect(date.toIso(), '2026-08-16');
      expect(CalendarDate.parse('2026-08-16'), date);
    });

    test('pads single digits, so text sorts in calendar order', () {
      expect(const CalendarDate(2026, 1, 5).toIso(), '2026-01-05');

      // The whole reason date columns can be indexed and range-queried as
      // text.
      final dates = ['2026-10-01', '2026-09-30', '2026-01-05']..sort();
      expect(dates, ['2026-01-05', '2026-09-30', '2026-10-01']);
    });

    test('rejects a malformed or impossible day', () {
      expect(() => CalendarDate.parse('16-08-2026'), throwsFormatException);
      expect(() => CalendarDate.parse('2026-8-16'), throwsFormatException);
      // DateTime would silently roll this to 2 March.
      expect(() => CalendarDate.parse('2026-02-30'), throwsFormatException);
      expect(() => CalendarDate.parse(''), throwsFormatException);
    });

    test('counts whole days across a daylight-saving boundary', () {
      // Computed in UTC on purpose: a 23-hour or 25-hour local day would
      // otherwise truncate a week to 6 days.
      const beforeDst = CalendarDate(2026, 3, 27);
      final afterDst = beforeDst.addDays(7);

      expect(afterDst, const CalendarDate(2026, 4, 3));
      expect(beforeDst.daysUntil(afterDst), 7);
      expect(afterDst.daysUntil(beforeDst), -7);
    });

    test('orders by day, not by string', () {
      const earlier = CalendarDate(2026, 9, 30);
      const later = CalendarDate(2026, 10, 1);

      expect(earlier.isBefore(later), isTrue);
      expect(later.isAfter(earlier), isTrue);
      expect(earlier.compareTo(earlier), 0);
    });

    test('weekday matches DateTime, so it lines up with day_of_week', () {
      // 16 Aug 2026 is a Sunday.
      expect(const CalendarDate(2026, 8, 16).weekday, DateTime.sunday);
    });
  });

  group('ProgressionRuleCodec', () {
    test('stores nothing at all for the default rule', () {
      // The common case shouldn't cost a JSON blob on every row.
      expect(
        ProgressionRuleCodec.encode(const ProgressionRule.fixed()),
        isNull,
      );
      expect(ProgressionRuleCodec.decode(null), const ProgressionRule.fixed());
      expect(ProgressionRuleCodec.decode(''), const ProgressionRule.fixed());
    });

    test('round-trips every rule', () {
      const rules = [
        ProgressionRule.linearWeekly(incrementKg: 2.5),
        ProgressionRule.linearWeekly(incrementKg: 2.5, ceilingKg: 100),
        ProgressionRule.doubleProgression(
          repsMin: 8,
          repsMax: 12,
          incrementKg: 2.5,
        ),
        ProgressionRule.topSetBackoff(backoffSets: 3, backoffPercent: 0.85),
      ];

      for (final rule in rules) {
        expect(
          ProgressionRuleCodec.decode(ProgressionRuleCodec.encode(rule)),
          rule,
          reason: '$rule',
        );
      }
    });

    test('reads a whole-number increment written as an int', () {
      // JSON gives back `2` for a value written as 2.0; a bare cast to double
      // would throw and take the builder screen with it.
      final rule = ProgressionRuleCodec.decode(
        '{"type":"linearWeekly","incrementKg":2}',
      );

      expect(rule, const ProgressionRule.linearWeekly(incrementKg: 2));
    });

    test('degrades to fixed for anything it cannot read', () {
      // Malformed, and a rule type from a newer build. Showing the plan as
      // written beats a screen that won't build — and nothing is written back,
      // so the unknown rule survives for the version that understands it.
      expect(
        ProgressionRuleCodec.decode('not json'),
        const ProgressionRule.fixed(),
      );
      expect(
        ProgressionRuleCodec.decode('{"type":"neuralNetworkAutoregulation"}'),
        const ProgressionRule.fixed(),
      );
      expect(ProgressionRuleCodec.decode('[]'), const ProgressionRule.fixed());
    });
  });
}
