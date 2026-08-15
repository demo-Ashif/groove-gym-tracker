import 'package:drift/drift.dart';

import '../../../domain/enums/training_enums.dart';
import '../../../domain/services/schedule_materializer.dart';
import '../app_database.dart';
import '../tables/plan_tables.dart';

part 'schedule_dao.g.dart';

/// The materialized calendar.
@DriftAccessor(tables: [ScheduledSessions, Programs])
class ScheduleDao extends DatabaseAccessor<AppDatabase>
    with _$ScheduleDaoMixin {
  ScheduleDao(super.attachedDatabase);

  /// Every day of a program, in date order.
  Stream<List<ScheduledSessionRow>> watchProgramSchedule(String programId) {
    return (select(scheduledSessions)
          ..where(
            (row) => row.programId.equals(programId) & row.deletedAt.isNull(),
          )
          ..orderBy([(row) => OrderingTerm(expression: row.date)]))
        .watch();
  }

  /// Days between two `YYYY-MM-DD` bounds, inclusive.
  ///
  /// A string range is a real range here: the format sorts lexicographically
  /// in exactly calendar order, which is why the column is text and not a
  /// timestamp.
  Stream<List<ScheduledSessionRow>> watchRange({
    required String fromDate,
    required String toDate,
  }) {
    return (select(scheduledSessions)
          ..where(
            (row) =>
                row.deletedAt.isNull() &
                row.date.isBiggerOrEqualValue(fromDate) &
                row.date.isSmallerOrEqualValue(toDate),
          )
          ..orderBy([(row) => OrderingTerm(expression: row.date)]))
        .watch();
  }

  Future<ScheduledSessionRow?> findById(String id) {
    return (select(scheduledSessions)
          ..where((row) => row.id.equals(id) & row.deletedAt.isNull()))
        .getSingleOrNull();
  }

  Future<List<ScheduledSessionRow>> loadProgramSchedule(String programId) {
    return (select(scheduledSessions)
          ..where(
            (row) => row.programId.equals(programId) & row.deletedAt.isNull(),
          )
          ..orderBy([(row) => OrderingTerm(expression: row.date)]))
        .get();
  }

  /// Applies a diff and stores the pattern that produced it, **in one
  /// transaction**.
  ///
  /// Partial application is the failure that matters: a calendar with the old
  /// days removed and the new ones missing is a program that has silently lost
  /// a week.
  Future<void> commitSchedule({
    required String programId,
    required ScheduleDiff diff,
    required String? encodedPattern,
  }) async {
    await transaction(() async {
      final now = DateTime.now();

      if (diff.toRemove.isNotEmpty) {
        // Soft delete, like everything else — a hard delete could not
        // propagate to another device (ADR §6.2 rule 5).
        await customUpdate(
          'UPDATE scheduled_sessions '
          'SET deleted_at = ?, updated_at = ?, sync_state = ? '
          'WHERE id IN (${List.filled(diff.toRemove.length, '?').join(', ')})',
          variables: [
            Variable<DateTime>(now),
            Variable<DateTime>(now),
            Variable<String>(SyncState.pendingDelete.name),
            ...diff.toRemove.map(Variable<String>.new),
          ],
          updates: {scheduledSessions},
        );
      }

      if (diff.toInsert.isNotEmpty) {
        await batch((batch) {
          for (final day in diff.toInsert) {
            batch.insert(
              scheduledSessions,
              ScheduledSessionsCompanion.insert(
                programId: programId,
                sessionTemplateId: Value(day.sessionTemplateId),
                date: day.date.toIso(),
                weekNumber: day.weekNumber,
                kind: day.kind,
                plannedDurationMin: Value(day.plannedDurationMin),
              ),
            );
          }
        });
      }

      await (update(programs)..where((row) => row.id.equals(programId))).write(
        ProgramsCompanion(
          schedulePattern: Value(encodedPattern),
          updatedAt: Value(now),
          syncState: const Value(SyncState.pendingUpdate),
        ),
      );
    });
  }

  Future<void> setStatus(String id, ScheduledSessionStatus status) async {
    await (update(scheduledSessions)..where((row) => row.id.equals(id))).write(
      ScheduledSessionsCompanion(
        status: Value(status),
        updatedAt: Value(DateTime.now()),
        syncState: const Value(SyncState.pendingUpdate),
      ),
    );
  }

  /// Converts a day to another kind — "this became a cricket day".
  ///
  /// Clears the template when the day stops being a gym day, so nothing
  /// downstream can read a prescription off a day that no longer has one.
  Future<void> convertKind({
    required String id,
    required ScheduledSessionKind kind,
    String? reason,
  }) async {
    await (update(scheduledSessions)..where((row) => row.id.equals(id))).write(
      ScheduledSessionsCompanion(
        kind: Value(kind),
        sessionTemplateId: kind == ScheduledSessionKind.gym
            ? const Value.absent()
            : const Value(null),
        overrideReason: Value(reason),
        updatedAt: Value(DateTime.now()),
        syncState: const Value(SyncState.pendingUpdate),
      ),
    );
  }

  /// Moves a day to another date (ADR §8.2 reschedule).
  Future<void> reschedule({required String id, required String date}) async {
    await (update(scheduledSessions)..where((row) => row.id.equals(id))).write(
      ScheduledSessionsCompanion(
        date: Value(date),
        updatedAt: Value(DateTime.now()),
        syncState: const Value(SyncState.pendingUpdate),
      ),
    );
  }
}
