import 'package:equatable/equatable.dart';

/// A calendar day with no time and no timezone.
///
/// A program starts on a *day*. Modelling that as a `DateTime` is the classic
/// off-by-one: `DateTime(2026, 8, 16)` is local midnight, and the moment it
/// crosses a timezone, a serializer or a UTC conversion it can become the
/// 15th. Every date column in the schema is `YYYY-MM-DD` text for the same
/// reason, and this is its counterpart in the domain.
///
/// Deliberately not comparable to a `DateTime`: converting is explicit, so
/// nobody accidentally compares a day to an instant.
class CalendarDate extends Equatable implements Comparable<CalendarDate> {
  const CalendarDate(this.year, this.month, this.day);

  /// The day currently showing on the user's own clock.
  factory CalendarDate.today({DateTime? now}) {
    final moment = now ?? DateTime.now();
    return CalendarDate(moment.year, moment.month, moment.day);
  }

  /// The day [moment] falls on, in local time.
  factory CalendarDate.from(DateTime moment) =>
      CalendarDate(moment.year, moment.month, moment.day);

  /// Parses `YYYY-MM-DD`, the storage format. Throws [FormatException] on
  /// anything else — a malformed date in a date column is a bug worth
  /// surfacing, not a value to guess at.
  factory CalendarDate.parse(String iso) {
    final match = _isoPattern.firstMatch(iso);
    if (match == null) {
      throw FormatException('Expected YYYY-MM-DD', iso);
    }

    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);

    // Catches 2026-02-30, which the pattern happily accepts: DateTime rolls
    // it over to March, so a mismatch means the input was not a real day.
    final normalized = DateTime(year, month, day);
    if (normalized.month != month || normalized.day != day) {
      throw FormatException('Not a real calendar day', iso);
    }

    return CalendarDate(year, month, day);
  }

  static final _isoPattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

  final int year;
  final int month;
  final int day;

  /// `YYYY-MM-DD`. Sorts lexicographically in exactly calendar order, which is
  /// why the schema can index and range-query date columns as text.
  String toIso() =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';

  /// Local midnight. Use only at the edge — formatting through `intl`, or
  /// comparing against a real timestamp.
  DateTime toDateTime() => DateTime(year, month, day);

  /// ISO-8601 weekday, 1 = Monday … 7 = Sunday. Matches
  /// `session_templates.day_of_week` and `DateTime.weekday`.
  int get weekday => toDateTime().weekday;

  CalendarDate addDays(int days) =>
      CalendarDate.from(toDateTime().add(Duration(days: days)));

  /// Whole days from this date to [other]; negative if [other] is earlier.
  ///
  /// Computed in UTC so a daylight-saving boundary can't turn 7 days into
  /// 6 days and 23 hours, which truncates to 6.
  int daysUntil(CalendarDate other) {
    final from = DateTime.utc(year, month, day);
    final to = DateTime.utc(other.year, other.month, other.day);
    return to.difference(from).inDays;
  }

  bool isBefore(CalendarDate other) => compareTo(other) < 0;
  bool isAfter(CalendarDate other) => compareTo(other) > 0;

  @override
  int compareTo(CalendarDate other) {
    if (year != other.year) return year.compareTo(other.year);
    if (month != other.month) return month.compareTo(other.month);
    return day.compareTo(other.day);
  }

  @override
  List<Object?> get props => [year, month, day];

  @override
  String toString() => toIso();
}
