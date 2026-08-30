import '../../core/logging/app_logger.dart';
import '../../domain/entities/insights.dart';
import '../../domain/enums/training_enums.dart';
import '../../domain/repositories/insights_repository.dart';
import '../../domain/services/trend_service.dart';
import '../../domain/values/calendar_date.dart';
import '../../domain/values/insights_range.dart';
import '../db/daos/insights_dao.dart';

/// Drift-backed analytics.
class InsightsRepositoryImpl implements InsightsRepository {
  const InsightsRepositoryImpl(this._dao);

  final InsightsDao _dao;

  @override
  Stream<AdherenceStats> watchAdherence(DateRange range) {
    return _dao
        .watchAdherenceTotals(from: _from(range), to: _to(range))
        .map(
          (totals) => AdherenceStats(
            plannedSets: totals.plannedSets,
            completedSets: totals.completedSets,
            plannedSessions: totals.plannedSessions,
            completedSessions: totals.completedSessions,
          ),
        );
  }

  @override
  Stream<SkipBreakdown> watchSkipBreakdown(DateRange range) {
    return _dao.watchSkipBreakdown(from: _from(range), to: _to(range)).map((
      rows,
    ) {
      final byReason = <SkipReason, int>{};
      for (final entry in rows.entries) {
        final reason = _parseSkipReason(entry.key);
        // A reason written by a newer version of the app is counted as
        // nothing rather than crashing a chart the user is looking at.
        if (reason == null) continue;
        byReason[reason] = (byReason[reason] ?? 0) + entry.value;
      }
      return SkipBreakdown(Map.unmodifiable(byReason));
    });
  }

  @override
  Stream<List<WeightPoint>> watchWeightTrend(
    DateRange range, {
    int movingAverageDays = 7,
  }) {
    return _dao.watchWeightPoints(from: _from(range), to: _to(range)).map((
      rows,
    ) {
      final points = [
        for (final row in rows)
          // `weight_kg IS NOT NULL` is in the query's where clause, so this is
          // a filter for the type system rather than a real branch.
          if (row.weightKg case final kg?)
            WeightPoint(date: CalendarDate.parse(row.date), kg: kg),
      ];

      return TrendService.withMovingAverage(
        points,
        windowDays: movingAverageDays,
      );
    });
  }

  String _from(DateRange range) => range.start?.toIso() ?? InsightsDao.minDate;

  String _to(DateRange range) => range.end?.toIso() ?? InsightsDao.maxDate;

  SkipReason? _parseSkipReason(String stored) {
    for (final reason in SkipReason.values) {
      if (reason.name == stored) return reason;
    }
    AppLogger.w('Unknown skip reason in set_logs: $stored', tag: 'Insights');
    return null;
  }
}
