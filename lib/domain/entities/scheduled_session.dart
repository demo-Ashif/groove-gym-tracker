import 'package:equatable/equatable.dart';

import '../enums/training_enums.dart';
import '../values/calendar_date.dart';

/// One dated day on the calendar (ADR §4.3 `scheduled_sessions`).
///
/// The whole program is materialized on commit — about 50 rows for ten weeks —
/// which makes the calendar, adherence and rescheduling trivially queryable
/// instead of recomputed from a recurrence rule on every read.
class ScheduledSession extends Equatable {
  const ScheduledSession({
    required this.id,
    required this.date,
    this.programId,
    required this.weekNumber,
    required this.kind,
    this.sessionTemplateId,
    this.status = ScheduledSessionStatus.upcoming,
    this.plannedDurationMin,
    this.overrideReason,
  });

  final String id;

  /// Null for a backfilled day that belongs to no program.
  final String? programId;

  final CalendarDate date;

  /// 1-based week of the program.
  final int weekNumber;

  final ScheduledSessionKind kind;

  /// Null for rest, cricket and custom days, which have no template behind
  /// them.
  final String? sessionTemplateId;

  final ScheduledSessionStatus status;
  final int? plannedDurationMin;

  /// Why a gym day became something else — set when the user converts a day,
  /// so a light week reads as intentional (ADR §8.2).
  final String? overrideReason;

  /// Whether this day is still open to being rewritten by a re-commit.
  ///
  /// A day the user has touched is history, and history must not lie
  /// (ADR §8.2) — re-committing a schedule may never overwrite it.
  bool get isUntouched => status == ScheduledSessionStatus.upcoming;

  @override
  List<Object?> get props => [
    id,
    programId,
    date,
    weekNumber,
    kind,
    sessionTemplateId,
    status,
    plannedDurationMin,
    overrideReason,
  ];
}
