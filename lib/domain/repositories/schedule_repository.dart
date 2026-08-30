import '../../core/error/result.dart';
import '../entities/scheduled_session.dart';
import '../enums/training_enums.dart';
import '../values/calendar_date.dart';
import '../values/schedule_pattern.dart';

/// The materialized calendar (ADR §8.2).
abstract interface class ScheduleRepository {
  /// Every day of a program, in date order.
  Stream<List<ScheduledSession>> watchProgramSchedule(String programId);

  /// One day by id. Null when it has been deleted — a stale deep link or a
  /// notification fired for a day that has since been rescheduled away.
  Future<Result<ScheduledSession?>> findById(String id);

  /// Days of the active program in an inclusive date range — the week strip
  /// and Today read this.
  ///
  /// Scoped to the active program on purpose. Programs may overlap in dates,
  /// but exactly one is active, and "what am I doing today" has to have one
  /// answer. Emits an empty list when no program is active.
  Stream<List<ScheduledSession>> watchActiveRange({
    required CalendarDate from,
    required CalendarDate to,
  });

  /// Expands [pattern] across the program and writes the difference.
  ///
  /// Safe to call repeatedly: days already in the past, and days the user has
  /// started, finished, skipped or converted, are never rewritten. Returns how
  /// many days were added and removed, so the UI can say what happened rather
  /// than just claiming success.
  Future<Result<({int added, int removed})>> commitSchedule({
    required String programId,
    required SchedulePattern pattern,
  });

  /// Creates a day that belongs to no program, for logging training that
  /// happened before the app did.
  ///
  /// A session log has to hang off a scheduled day — that is what makes the
  /// calendar, adherence and history queryable — so backfilling one session
  /// means creating the day it happened on. The day is deliberately outside
  /// any program: it is a record, not part of a plan, and it must not shift
  /// the adherence denominator of a block it was never in.
  Future<Result<ScheduledSession>> createBackfillDay({
    required CalendarDate date,
  });

  Future<Result<void>> setStatus({
    required String id,
    required ScheduledSessionStatus status,
  });

  /// "This became a cricket day." The reason is stored so a light week reads
  /// as intentional rather than as a gap.
  Future<Result<void>> convertKind({
    required String id,
    required ScheduledSessionKind kind,
    String? reason,
  });

  Future<Result<void>> reschedule({
    required String id,
    required CalendarDate date,
  });
}
