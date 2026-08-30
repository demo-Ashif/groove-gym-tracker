import '../entities/insights.dart';

/// Smoothing for sparse, noisy series.
///
/// Pure and clock-free, like `MetricsService` — this feeds a chart the user
/// reads as truth, and a wrong average is invisible until months of history
/// have been drawn from it.
abstract final class TrendService {
  /// Adds a trailing moving average to weigh-ins, over **calendar days**
  /// rather than over the previous N entries.
  ///
  /// That distinction is the whole point: weighing yourself twice in one week
  /// and then not again for ten days is normal, and a "last 7 entries" mean
  /// would silently average a fortnight of drift into today's number.
  ///
  /// [points] must be ascending by date, which is how the repository reads
  /// them. Points already carrying an average are recomputed, so calling this
  /// twice is safe.
  static List<WeightPoint> withMovingAverage(
    List<WeightPoint> points, {
    int windowDays = 7,
  }) {
    if (points.isEmpty) return const [];

    final result = <WeightPoint>[];
    // Left edge of the window. Only ever moves forward, so the whole pass is
    // linear rather than quadratic.
    var start = 0;
    var sum = 0.0;

    for (var i = 0; i < points.length; i++) {
      sum += points[i].kg;

      while (points[start].date.daysUntil(points[i].date) > windowDays - 1) {
        sum -= points[start].kg;
        start++;
      }

      final count = i - start + 1;
      result.add(
        WeightPoint(
          date: points[i].date,
          kg: points[i].kg,
          averageKg: sum / count,
        ),
      );
    }

    return List.unmodifiable(result);
  }

  /// Change across the series, newest minus oldest. Null unless there are two
  /// points to compare — a single weigh-in is not a trend.
  static double? change(List<WeightPoint> points) {
    if (points.length < 2) return null;
    return points.last.kg - points.first.kg;
  }
}
