import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

/// Locale-aware number, date and duration formatting (ADR §12.2 rule 5).
///
/// Nothing here returns a sentence. Anything with a word in it — "3 sets",
/// "1h 30m" — belongs in ARB with placeholders, because word order and plural
/// rules differ by language. This class only produces the numeric and
/// symbolic parts those messages interpolate.
class Formatters {
  Formatters(this.locale);

  factory Formatters.of(BuildContext context) =>
      Formatters(Localizations.localeOf(context).toString());

  final String locale;

  /// Weights and other one-decimal values: `78.4`, or `78,4` where the locale
  /// says so. Digits render in the locale's own glyphs.
  String decimal(num value, {int fractionDigits = 1}) =>
      NumberFormat.decimalPatternDigits(
        locale: locale,
        decimalDigits: fractionDigits,
      ).format(value);

  String integer(num value) =>
      NumberFormat.decimalPattern(locale).format(value);

  /// `0.87` → `87%`.
  String percent(double fraction, {int fractionDigits = 0}) =>
      NumberFormat.decimalPercentPattern(
        locale: locale,
        decimalDigits: fractionDigits,
      ).format(fraction);

  /// Reads a user-typed weight back, accepting the locale's decimal
  /// separator — `78,4` is what most of Europe types and it must not parse as
  /// 784. Returns null rather than throwing, so a field can show a validation
  /// state instead of crashing.
  double? parseDecimal(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;
    try {
      return NumberFormat.decimalPattern(locale).parse(trimmed).toDouble();
    } on FormatException {
      // Fall back to the invariant form, so a keyboard that only offers '.'
      // still works in a comma locale.
      return double.tryParse(trimmed.replaceAll(',', '.'));
    }
  }

  /// `Sun, 16 Aug` — a session card's date line.
  String mediumDate(DateTime date) => DateFormat.MMMEd(locale).format(date);

  /// `16 August 2026`.
  String longDate(DateTime date) => DateFormat.yMMMMd(locale).format(date);

  /// `Sun` — the week strip.
  String shortWeekday(DateTime date) => DateFormat.E(locale).format(date);

  /// `Sunday` — a sheet title, where there is room for the real word.
  String longWeekday(DateTime date) => DateFormat.EEEE(locale).format(date);

  /// `19:30`, or `7:30 PM`, per locale.
  String timeOfDay(DateTime time) => DateFormat.jm(locale).format(time);

  /// `1:30` / `12:05` — the rest timer. Symbols only, so it needs no
  /// translation, and it never rolls over into hours because no rest interval
  /// does.
  String clock(Duration duration) {
    final total = duration.isNegative ? Duration.zero : duration;
    final minutes = total.inMinutes;
    final seconds = total.inSeconds.remainder(60);
    return '${integer(minutes)}:${seconds.toString().padLeft(2, '0')}';
  }

  /// Split for an ARB message like
  /// `"{hours}h {minutes}m"` — the words stay in the translation.
  ({int hours, int minutes}) hoursAndMinutes(Duration duration) {
    final total = duration.isNegative ? Duration.zero : duration;
    return (hours: total.inHours, minutes: total.inMinutes.remainder(60));
  }
}
