import 'package:equatable/equatable.dart';

import '../enums/training_enums.dart';
import '../services/metrics_service.dart';
import '../values/calendar_date.dart';

/// What a window of training amounted to against what it prescribed
/// (ADR §11.2 card 1).
///
/// Sets and sessions are counted separately on purpose: turning up four times
/// out of four and cutting every session short is a different failure from
/// missing a day entirely, and one number cannot say which happened.
class AdherenceStats extends Equatable {
  const AdherenceStats({
    required this.plannedSets,
    required this.completedSets,
    required this.plannedSessions,
    required this.completedSessions,
  });

  static const empty = AdherenceStats(
    plannedSets: 0,
    completedSets: 0,
    plannedSessions: 0,
    completedSessions: 0,
  );

  final int plannedSets;
  final int completedSets;

  /// Gym days on the calendar in the window, whatever became of them.
  final int plannedSessions;

  /// Days that finished completed or partial.
  final int completedSessions;

  /// 0–1, or null when nothing was planned.
  ///
  /// Null rather than zero: a week with no program is not a week you failed
  /// (ADR §11.2).
  double? get adherence => MetricsService.adherence(
    completedSets: completedSets,
    plannedSets: plannedSets,
  );

  /// Whether the window holds anything worth drawing. A range with no plan and
  /// no logs gets the empty state, not a 0% ring.
  bool get hasData =>
      plannedSets > 0 || completedSets > 0 || plannedSessions > 0;

  @override
  List<Object?> get props => [
    plannedSets,
    completedSets,
    plannedSessions,
    completedSessions,
  ];
}

/// Skipped sets broken out by reason.
///
/// A bad week has to be legible, not just smaller (ADR §4.4) — pain is the one
/// reason that changes what you should do next, so it is kept distinguishable
/// rather than folded into a single "missed" count.
class SkipBreakdown extends Equatable {
  const SkipBreakdown(this.byReason);

  static const empty = SkipBreakdown({});

  final Map<SkipReason, int> byReason;

  int get total => byReason.values.fold(0, (sum, count) => sum + count);

  int get painSkips => byReason[SkipReason.pain] ?? 0;

  bool get isEmpty => byReason.isEmpty;

  /// Reasons that actually occurred, heaviest first — nothing renders a zero.
  List<MapEntry<SkipReason, int>> get ranked {
    final entries = byReason.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }

  @override
  List<Object?> get props => [byReason];
}

/// One weigh-in on the trend, with the smoothed value drawn through it.
///
/// [averageKg] is the line the user should read: daily bodyweight swings
/// ±1.5 kg on water alone, so the raw dot is faint and the average is the
/// signal (ADR §11.2 card 2).
class WeightPoint extends Equatable {
  const WeightPoint({required this.date, required this.kg, this.averageKg});

  final CalendarDate date;
  final double kg;
  final double? averageKg;

  @override
  List<Object?> get props => [date, kg, averageKg];
}
