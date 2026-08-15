import 'package:equatable/equatable.dart';

import '../entities/exercise.dart';
import '../entities/plan.dart';
import '../entities/session_log.dart';
import '../enums/training_enums.dart';

/// What a finished session amounts to.
class SessionSummary extends Equatable {
  const SessionSummary({
    required this.completedSets,
    required this.plannedSets,
    required this.skippedSets,
    required this.tonnageKg,
    required this.duration,
    required this.skipReasons,
  });

  final int completedSets;
  final int plannedSets;
  final int skippedSets;
  final double tonnageKg;
  final Duration duration;

  /// Skips broken out by reason. A bad week has to be legible, not just
  /// smaller (ADR §4.4).
  final Map<SkipReason, int> skipReasons;

  /// 0–1. Null when nothing was planned, which is different from zero:
  /// an unplanned session cannot be "0% adherent".
  double? get adherence =>
      plannedSets == 0 ? null : completedSets / plannedSets;

  @override
  List<Object?> get props => [
    completedSets,
    plannedSets,
    skippedSets,
    tonnageKg,
    duration,
    skipReasons,
  ];
}

/// The derived numbers (ADR §4.4).
///
/// Pure functions over entities — no database, no clock — because these feed
/// every chart in the app and a wrong one is invisible until months of history
/// have been drawn from it.
abstract final class MetricsService {
  /// Estimated one-rep max, Epley: `w × (1 + reps/30)`.
  ///
  /// Returns null where the number would be fiction:
  ///
  /// - **Above 12 reps** the formula diverges badly from reality.
  /// - **Without an external load** — bodyweight, bands, time, distance —
  ///   there is nothing to extrapolate from.
  ///
  /// e1RM is the primary strength metric precisely because rep ranges shift by
  /// design across cycles (4×8 → 5×5 → top-set 3s), which makes raw top weight
  /// read as noise.
  static double? e1rm({
    required double? weightKg,
    required int? reps,
    required LoadType loadType,
  }) {
    if (!loadType.isLoadable) return null;
    if (weightKg == null || reps == null) return null;
    if (weightKg <= 0 || reps <= 0 || reps > 12) return null;

    return weightKg * (1 + reps / 30);
  }

  /// e1RM for a set, or null if it doesn't qualify.
  static double? setE1rm(SetLog set, Exercise exercise) {
    if (!set.isCompleted) return null;
    return e1rm(
      weightKg: set.weightKg,
      reps: set.reps,
      loadType: exercise.loadType,
    );
  }

  /// Work done in one set, in kg.
  ///
  /// The multiplier is the fiddly part, and getting it wrong quietly doubles
  /// or halves every volume chart:
  ///
  /// - A **unilateral** exercise logged as `both` was worked twice — once per
  ///   side — so it counts double. Logged as one side, it counts once.
  /// - A **bilateral dumbbell** exercise is logged per hand, so both hands
  ///   count.
  ///
  /// The two never compound: a single-arm dumbbell row is one dumbbell in one
  /// hand, so it takes the unilateral multiplier and not the load-type one.
  static double setTonnage(SetLog set, Exercise exercise) {
    if (!set.isCompleted) return 0;

    final weight = set.weightKg;
    final reps = set.reps;
    if (weight == null || reps == null || weight <= 0 || reps <= 0) return 0;

    final multiplier = exercise.isUnilateral
        ? (set.side == SetSide.both ? 2 : 1)
        : exercise.loadType.tonnageMultiplier;

    return weight * reps * multiplier;
  }

  static double sessionTonnage(
    List<SetLog> sets,
    Map<String, Exercise> exercisesById,
  ) {
    var total = 0.0;
    for (final set in sets) {
      final exercise = exercisesById[set.exerciseId];
      // An unknown exercise contributes nothing rather than throwing: a chart
      // must not die because one catalog row was purged.
      if (exercise == null) continue;
      total += setTonnage(set, exercise);
    }
    return total;
  }

  /// Sets the template prescribes, counting only what was actually planned.
  static int plannedSets(SessionTemplate? template) {
    if (template == null) return 0;
    return template.totalSets;
  }

  /// Everything the finalize screen and the phase report need, in one pass.
  static SessionSummary summarize({
    required SessionLog log,
    required SessionTemplate? template,
    required Map<String, Exercise> exercisesById,
  }) {
    final skipReasons = <SkipReason, int>{};
    for (final set in log.sets) {
      if (set.skipReason case final reason?) {
        skipReasons[reason] = (skipReasons[reason] ?? 0) + 1;
      }
    }

    return SessionSummary(
      completedSets: log.completedSets,
      plannedSets: plannedSets(template),
      skippedSets: log.skippedSets,
      tonnageKg: sessionTonnage(log.sets, exercisesById),
      duration: log.duration,
      skipReasons: skipReasons,
    );
  }

  /// Adherence across many sessions — the number the app exists to produce
  /// (ADR §11.2).
  ///
  /// Null rather than zero when nothing was planned: a week with no program is
  /// not a week you failed.
  static double? adherence({
    required int completedSets,
    required int plannedSets,
  }) => plannedSets == 0 ? null : completedSets / plannedSets;
}
