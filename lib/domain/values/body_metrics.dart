import 'dart:math' as math;

/// Which units the user reads and enters body measurements in.
///
/// **Display only.** Everything is stored in kilograms and centimetres, and
/// converted at the edge — a store that holds "180" without knowing whether
/// that is centimetres or pounds is a store that will eventually be read
/// wrong. Changing this preference re-renders; it never rewrites data.
enum UnitSystem {
  /// Kilograms and centimetres.
  metric,

  /// Stones and pounds, feet and inches. What "UK" means on a gym scale.
  imperial;

  bool get isMetric => this == UnitSystem.metric;
}

/// Self-reported. Feeds BMI's interpretation bands and nothing else today;
/// [unspecified] is a first-class answer, not a missing value.
enum Gender { female, male, other, unspecified }

/// Unit conversion, in one place.
///
/// All of these are exact definitions rather than rounded constants: an inch
/// is 2.54 cm and a pound is 0.45359237 kg by definition, so a round trip
/// through them does not drift.
abstract final class BodyUnits {
  static const _kgPerPound = 0.45359237;
  static const _cmPerInch = 2.54;
  static const _poundsPerStone = 14;
  static const _inchesPerFoot = 12;

  static double kgToPounds(double kg) => kg / _kgPerPound;

  static double poundsToKg(double pounds) => pounds * _kgPerPound;

  static double cmToInches(double cm) => cm / _cmPerInch;

  static double inchesToCm(double inches) => inches * _cmPerInch;

  /// Whole stones plus the remaining pounds — how a UK scale reads.
  static ({int stone, double pounds}) kgToStonePounds(double kg) {
    final totalPounds = kgToPounds(kg);
    final stone = totalPounds ~/ _poundsPerStone;
    return (stone: stone, pounds: totalPounds - stone * _poundsPerStone);
  }

  static double stonePoundsToKg({required int stone, required double pounds}) =>
      poundsToKg(stone * _poundsPerStone + pounds);

  /// Whole feet plus the remaining inches.
  static ({int feet, double inches}) cmToFeetInches(double cm) {
    final totalInches = cmToInches(cm);
    final feet = totalInches ~/ _inchesPerFoot;
    return (feet: feet, inches: totalInches - feet * _inchesPerFoot);
  }

  static double feetInchesToCm({required int feet, required double inches}) =>
      inchesToCm(feet * _inchesPerFoot + inches);
}

/// How a BMI value reads. WHO bands, which are the ones every clinician and
/// every other app uses.
enum BmiBand { underweight, healthy, overweight, obese }

/// Body Mass Index.
///
/// Derived, never stored: height and weight are the facts, and a stored BMI
/// would go stale the moment either changed. It is also a population statistic
/// with well-known limits on a lifter — a heavy, lean athlete reads as
/// "overweight" — so the app shows the number and its band without editorial.
abstract final class Bmi {
  /// Null unless both inputs are present and sane. Returning null rather than
  /// a wrong number matters: this is rendered next to real measurements, and a
  /// plausible-looking wrong value is worse than a blank.
  static double? calculate({double? weightKg, double? heightCm}) {
    if (weightKg == null || heightCm == null) return null;
    if (weightKg <= 0 || heightCm <= 0) return null;

    final heightM = heightCm / 100;
    final value = weightKg / math.pow(heightM, 2);

    // Beyond these the inputs are a typo, not a body.
    if (value < 5 || value > 100) return null;
    return value;
  }

  static BmiBand? bandFor(double? bmi) => switch (bmi) {
    null => null,
    < 18.5 => BmiBand.underweight,
    < 25 => BmiBand.healthy,
    < 30 => BmiBand.overweight,
    _ => BmiBand.obese,
  };
}
