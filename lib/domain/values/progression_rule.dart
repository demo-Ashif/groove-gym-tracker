import 'package:equatable/equatable.dart';

/// How next week's targets are derived from this week's (ADR §4.3
/// `exercise_templates.progression_rule`).
///
/// The point is that the app **pre-fills** the next session instead of asking.
/// A sealed hierarchy rather than a `Map` so every consumer has to handle
/// every rule, and a rule the app doesn't understand can't silently become
/// "no progression".
///
/// Stored as JSON in the data layer; the codec lives there, not here — the
/// domain has no opinion about serialization.
sealed class ProgressionRule extends Equatable {
  const ProgressionRule();

  /// Targets stay where the plan put them. The default, and the honest one
  /// for accessory work.
  const factory ProgressionRule.fixed() = FixedProgression;

  /// "+2.5 kg/week" — the most common thing a coach writes.
  const factory ProgressionRule.linearWeekly({
    required double incrementKg,
    double? ceilingKg,
  }) = LinearWeeklyProgression;

  /// "Add a rep each week until the top of the range, then add load and drop
  /// back to the bottom." Double progression, the standard hypertrophy scheme.
  const factory ProgressionRule.doubleProgression({
    required int repsMin,
    required int repsMax,
    required double incrementKg,
  }) = DoubleProgression;

  /// "Top set, then N back-off sets at a percentage of it."
  const factory ProgressionRule.topSetBackoff({
    required int backoffSets,
    required double backoffPercent,
  }) = TopSetBackoffProgression;
}

final class FixedProgression extends ProgressionRule {
  const FixedProgression();

  @override
  List<Object?> get props => const [];
}

final class LinearWeeklyProgression extends ProgressionRule {
  const LinearWeeklyProgression({required this.incrementKg, this.ceilingKg});

  final double incrementKg;

  /// Stop adding load past this, so a linear rule doesn't prescribe something
  /// absurd by week ten.
  final double? ceilingKg;

  @override
  List<Object?> get props => [incrementKg, ceilingKg];
}

final class DoubleProgression extends ProgressionRule {
  const DoubleProgression({
    required this.repsMin,
    required this.repsMax,
    required this.incrementKg,
  });

  final int repsMin;
  final int repsMax;
  final double incrementKg;

  @override
  List<Object?> get props => [repsMin, repsMax, incrementKg];
}

final class TopSetBackoffProgression extends ProgressionRule {
  const TopSetBackoffProgression({
    required this.backoffSets,
    required this.backoffPercent,
  });

  final int backoffSets;

  /// Fraction of the top set's load, e.g. `0.85`.
  final double backoffPercent;

  @override
  List<Object?> get props => [backoffSets, backoffPercent];
}
