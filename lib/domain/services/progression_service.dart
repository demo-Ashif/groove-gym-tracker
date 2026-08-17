import 'package:equatable/equatable.dart';

import '../entities/plan.dart';
import '../entities/session_log.dart';
import '../values/progression_rule.dart';

/// What a set chip is pre-filled with before the user touches it.
class SetPrefill extends Equatable {
  const SetPrefill({this.weightKg, this.reps});

  final double? weightKg;
  final int? reps;

  @override
  List<Object?> get props => [weightKg, reps];
}

/// Turns a prescription plus last week's performance into the numbers a set
/// chip opens with (ADR §4.3, §9.2).
///
/// This is what makes one tap equal one set: the 90% path is that the
/// suggestion is right and the user simply confirms it. Getting it wrong is
/// worse than having no suggestion, because a wrong number that looks
/// authoritative gets logged.
abstract final class ProgressionService {
  /// Suggests load and reps for the set at [setIndex].
  ///
  /// [lastSet] is the most recent *completed* set of this exercise, from any
  /// previous session. [weeksElapsed] is how many weeks have passed since it —
  /// a linear rule that missed a week should not silently skip its increment.
  static SetPrefill suggest({
    required ExerciseTemplate template,
    SetLog? lastSet,
    int setIndex = 0,
    int weeksElapsed = 1,
  }) {
    final baseWeight = lastSet?.weightKg ?? template.targetLoadKg;
    final targetReps = template.targetReps;

    return switch (template.progression) {
      FixedProgression() => SetPrefill(
        weightKg: baseWeight,
        reps: targetReps ?? lastSet?.reps,
      ),

      LinearWeeklyProgression(:final incrementKg, :final ceilingKg) =>
        SetPrefill(
          weightKg: _capped(
            // No previous set means this is week one of the exercise: the
            // prescription stands as written rather than being pre-advanced.
            lastSet == null
                ? baseWeight
                : _plus(baseWeight, incrementKg * weeksElapsed),
            ceilingKg,
          ),
          reps: targetReps ?? lastSet?.reps,
        ),

      DoubleProgression(:final repsMin, :final repsMax, :final incrementKg) =>
        _doubleProgression(
          baseWeight: baseWeight,
          lastReps: lastSet?.reps,
          repsMin: repsMin,
          repsMax: repsMax,
          incrementKg: incrementKg,
        ),

      TopSetBackoffProgression(:final backoffPercent) => SetPrefill(
        // The first set is the top set; everything after it is a back-off at a
        // percentage of it.
        weightKg: setIndex == 0
            ? baseWeight
            : _rounded(_times(baseWeight, backoffPercent)),
        reps: targetReps ?? lastSet?.reps,
      ),
    };
  }

  /// Add reps until the top of the range, then add load and drop back to the
  /// bottom. The standard hypertrophy scheme.
  ///
  /// The range here belongs to the **rule**, not to the prescription: a slot
  /// prescribes one rep number, and choosing double progression is what
  /// introduces a range to climb. That keeps the plan editor to a single reps
  /// stepper without losing the scheme.
  static SetPrefill _doubleProgression({
    required double? baseWeight,
    required int? lastReps,
    required int repsMin,
    required int repsMax,
    required double incrementKg,
  }) {
    if (lastReps == null) {
      return SetPrefill(weightKg: baseWeight, reps: repsMin);
    }

    if (lastReps >= repsMax) {
      return SetPrefill(
        weightKg: _plus(baseWeight, incrementKg),
        reps: repsMin,
      );
    }

    // Still inside the range: one more rep at the same load. Clamped so a set
    // logged above the range can't suggest something past it.
    return SetPrefill(
      weightKg: baseWeight,
      reps: (lastReps + 1).clamp(repsMin, repsMax),
    );
  }

  static double? _plus(double? value, double delta) =>
      value == null ? null : value + delta;

  static double? _times(double? value, double factor) =>
      value == null ? null : value * factor;

  static double? _capped(double? value, double? ceiling) {
    if (value == null) return null;
    if (ceiling == null) return value;
    return value > ceiling ? ceiling : value;
  }

  /// Back-off loads land on something loadable. 2.5 kg is the smallest pair of
  /// plates most gyms have, and a suggestion of 71.4 kg is a suggestion nobody
  /// can follow.
  static double? _rounded(double? value) {
    if (value == null) return null;
    return (value / 2.5).round() * 2.5;
  }
}
