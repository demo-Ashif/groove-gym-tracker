import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/check_in_tables.dart';
import '../tables/log_tables.dart';
import '../tables/plan_tables.dart';

part 'insights_dao.g.dart';

/// One aggregate row for a window of training.
class AdherenceTotals {
  const AdherenceTotals({
    required this.plannedSets,
    required this.completedSets,
    required this.plannedSessions,
    required this.completedSessions,
  });

  final int plannedSets;
  final int completedSets;
  final int plannedSessions;
  final int completedSessions;
}

/// The analytics reads (ADR §11.3).
///
/// **Aggregation happens in SQL, never in Dart.** These queries run over every
/// set the user has ever logged; folding that on the UI thread would be a
/// dropped frame per rebuild once history passes a few months.
///
/// The date bounds are `YYYY-MM-DD` strings compared with `>=` / `<=`. That
/// works because the format sorts lexicographically in exactly calendar order,
/// which is why every date column in the schema is text.
@DriftAccessor(
  tables: [
    ScheduledSessions,
    SessionTemplates,
    BlockTemplates,
    ExerciseTemplates,
    SessionLogs,
    SetLogs,
    CheckIns,
  ],
)
class InsightsDao extends DatabaseAccessor<AppDatabase>
    with _$InsightsDaoMixin {
  InsightsDao(super.attachedDatabase);

  /// Widened bounds for an open-ended range. Both sort outside any real date,
  /// so `All` is the same query shape as every other filter rather than a
  /// second branch that can drift out of step.
  static const minDate = '0000-01-01';
  static const maxDate = '9999-12-31';

  /// Planned and completed work inside a window.
  ///
  /// Planned sets come from the **templates** behind the scheduled days, not
  /// from the logs — that is the whole point of keeping prescription and
  /// record apart. A day whose template was deleted contributes zero planned
  /// sets rather than dropping the day, because the sets that were logged
  /// against it still happened.
  Stream<AdherenceTotals> watchAdherenceTotals({
    required String from,
    required String to,
  }) {
    // Four correlated aggregates in one statement, so a card shows four
    // numbers computed over one consistent snapshot instead of four streams
    // that can land a frame apart.
    const sql = '''
SELECT
  (SELECT COALESCE(SUM(et.target_sets), 0)
     FROM scheduled_sessions ss
     JOIN session_templates st
       ON st.id = ss.session_template_id AND st.deleted_at IS NULL
     JOIN block_templates bt
       ON bt.session_template_id = st.id AND bt.deleted_at IS NULL
     JOIN exercise_templates et
       ON et.block_template_id = bt.id AND et.deleted_at IS NULL
    WHERE ss.deleted_at IS NULL AND ss.date >= ? AND ss.date <= ?
  ) AS planned_sets,
  (SELECT COUNT(*)
     FROM set_logs sl
     JOIN session_logs l
       ON l.id = sl.session_log_id AND l.deleted_at IS NULL
     JOIN scheduled_sessions ss
       ON ss.id = l.scheduled_session_id AND ss.deleted_at IS NULL
    WHERE sl.deleted_at IS NULL AND sl.status = 'done'
      AND ss.date >= ? AND ss.date <= ?
  ) AS completed_sets,
  (SELECT COUNT(*)
     FROM scheduled_sessions ss
    WHERE ss.deleted_at IS NULL AND ss.kind = 'gym'
      AND ss.date >= ? AND ss.date <= ?
  ) AS planned_sessions,
  (SELECT COUNT(*)
     FROM scheduled_sessions ss
    WHERE ss.deleted_at IS NULL AND ss.kind = 'gym'
      AND ss.status IN ('completed', 'partial')
      AND ss.date >= ? AND ss.date <= ?
  ) AS completed_sessions
''';

    return customSelect(
      sql,
      // Positional, in statement order: from/to once per subquery.
      variables: [
        for (var i = 0; i < 4; i++) ...[
          Variable.withString(from),
          Variable.withString(to),
        ],
      ],
      // Without this the stream never re-runs: a raw query has no idea which
      // tables it touched, so logging a set would leave the ring frozen.
      readsFrom: {
        scheduledSessions,
        sessionTemplates,
        blockTemplates,
        exerciseTemplates,
        sessionLogs,
        setLogs,
      },
    ).map((row) {
      return AdherenceTotals(
        plannedSets: row.read<int>('planned_sets'),
        completedSets: row.read<int>('completed_sets'),
        plannedSessions: row.read<int>('planned_sessions'),
        completedSessions: row.read<int>('completed_sessions'),
      );
    }).watchSingle();
  }

  /// Skipped sets in a window, grouped by reason. Reasons that never occurred
  /// are absent rather than zero.
  Stream<Map<String, int>> watchSkipBreakdown({
    required String from,
    required String to,
  }) {
    const sql = '''
SELECT sl.skip_reason AS reason, COUNT(*) AS total
  FROM set_logs sl
  JOIN session_logs l
    ON l.id = sl.session_log_id AND l.deleted_at IS NULL
  JOIN scheduled_sessions ss
    ON ss.id = l.scheduled_session_id AND ss.deleted_at IS NULL
 WHERE sl.deleted_at IS NULL AND sl.skip_reason IS NOT NULL
   AND ss.date >= ? AND ss.date <= ?
 GROUP BY sl.skip_reason
''';

    return customSelect(
      sql,
      variables: [Variable.withString(from), Variable.withString(to)],
      readsFrom: {setLogs, sessionLogs, scheduledSessions},
    ).watch().map((rows) {
      return {
        for (final row in rows)
          row.read<String>('reason'): row.read<int>('total'),
      };
    });
  }

  /// Weigh-ins in a window, oldest first — the order a trend is drawn in.
  ///
  /// Check-ins carrying only a waist measurement are excluded rather than
  /// plotted as a gap.
  Stream<List<CheckInRow>> watchWeightPoints({
    required String from,
    required String to,
  }) {
    return (select(checkIns)
          ..where(
            (row) =>
                row.deletedAt.isNull() &
                row.weightKg.isNotNull() &
                row.date.isBiggerOrEqualValue(from) &
                row.date.isSmallerOrEqualValue(to),
          )
          ..orderBy([(row) => OrderingTerm(expression: row.date)]))
        .watch();
  }
}
