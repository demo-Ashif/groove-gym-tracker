import '../entities/insights.dart';
import '../values/insights_range.dart';

/// Aggregates over a window of training (ADR §11).
///
/// Every method is a live query the database aggregates — never a full-history
/// fold in Dart on the UI thread (ADR §11.3). Each returns its own stream so a
/// card that has nothing to show can be rebuilt without touching the others.
abstract interface class InsightsRepository {
  /// Planned versus completed sets and sessions inside [range].
  Stream<AdherenceStats> watchAdherence(DateRange range);

  /// Skipped sets in [range], broken out by reason.
  Stream<SkipBreakdown> watchSkipBreakdown(DateRange range);

  /// Weigh-ins in [range], oldest first, each carrying the trailing
  /// [movingAverageDays]-day average drawn through it.
  Stream<List<WeightPoint>> watchWeightTrend(
    DateRange range, {
    int movingAverageDays,
  });
}
