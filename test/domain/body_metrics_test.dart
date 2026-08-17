import 'package:flutter_test/flutter_test.dart';
import 'package:groove/domain/values/body_metrics.dart';

/// Unit conversion and BMI. Pure maths, so it is tested as maths — these
/// numbers end up next to real measurements, where a plausible-looking wrong
/// value is worse than a blank.
void main() {
  group('unit conversion', () {
    test('round-trips weight without drift', () {
      for (final kg in [45.0, 72.5, 83.3, 120.0]) {
        final imperial = BodyUnits.kgToStonePounds(kg);
        final back = BodyUnits.stonePoundsToKg(
          stone: imperial.stone,
          pounds: imperial.pounds,
        );
        expect(back, closeTo(kg, 0.0001), reason: '$kg kg');
      }
    });

    test('round-trips height without drift', () {
      for (final cm in [150.0, 178.0, 183.5, 201.0]) {
        final imperial = BodyUnits.cmToFeetInches(cm);
        final back = BodyUnits.feetInchesToCm(
          feet: imperial.feet,
          inches: imperial.inches,
        );
        expect(back, closeTo(cm, 0.0001), reason: '$cm cm');
      }
    });

    test('uses the exact definitions, not rounded constants', () {
      // A pound is 0.45359237 kg and an inch is 2.54 cm by definition.
      expect(BodyUnits.poundsToKg(1), closeTo(0.45359237, 1e-9));
      expect(BodyUnits.inchesToCm(1), closeTo(2.54, 1e-9));
    });

    test('splits into whole units the way a scale reads', () {
      // 12 st 7 lb.
      final imperial = BodyUnits.kgToStonePounds(
        BodyUnits.stonePoundsToKg(stone: 12, pounds: 7),
      );
      expect(imperial.stone, 12);
      expect(imperial.pounds, closeTo(7, 0.0001));

      final height = BodyUnits.cmToFeetInches(
        BodyUnits.feetInchesToCm(feet: 5, inches: 10),
      );
      expect(height.feet, 5);
      expect(height.inches, closeTo(10, 0.0001));
    });
  });

  group('BMI', () {
    test('computes the standard formula', () {
      // 80 kg at 1.80 m -> 24.69.
      expect(Bmi.calculate(weightKg: 80, heightCm: 180), closeTo(24.69, 0.01));
    });

    test('is null when either input is missing', () {
      expect(Bmi.calculate(weightKg: 80), isNull);
      expect(Bmi.calculate(heightCm: 180), isNull);
      expect(Bmi.calculate(), isNull);
    });

    test('refuses impossible inputs rather than returning a number', () {
      expect(Bmi.calculate(weightKg: 0, heightCm: 180), isNull);
      expect(Bmi.calculate(weightKg: 80, heightCm: 0), isNull);
      expect(Bmi.calculate(weightKg: -80, heightCm: 180), isNull);
      // A weight entered in pounds against a height in cm — the classic unit
      // mix-up, and it must not render as a confident 55.
      expect(Bmi.calculate(weightKg: 80, heightCm: 12), isNull);
    });

    test('bands follow the WHO boundaries', () {
      expect(Bmi.bandFor(17), BmiBand.underweight);
      expect(Bmi.bandFor(18.5), BmiBand.healthy);
      expect(Bmi.bandFor(24.9), BmiBand.healthy);
      expect(Bmi.bandFor(25), BmiBand.overweight);
      expect(Bmi.bandFor(29.9), BmiBand.overweight);
      expect(Bmi.bandFor(30), BmiBand.obese);
      expect(Bmi.bandFor(null), isNull);
    });
  });
}
