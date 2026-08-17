import 'package:drift/drift.dart';

import '../../../domain/enums/training_enums.dart';
import '../app_database.dart';
import '../tables/check_in_tables.dart';

part 'check_in_dao.g.dart';

/// Reads and writes body measurements.
@DriftAccessor(tables: [CheckIns])
class CheckInDao extends DatabaseAccessor<AppDatabase> with _$CheckInDaoMixin {
  CheckInDao(super.attachedDatabase);

  /// Newest first. `YYYY-MM-DD` sorts lexicographically in calendar order,
  /// which is why the column is text.
  Stream<List<CheckInRow>> watchCheckIns({int limit = 200}) {
    return (select(checkIns)
          ..where((row) => row.deletedAt.isNull())
          ..orderBy([(row) => OrderingTerm.desc(row.date)])
          ..limit(limit))
        .watch();
  }

  /// The latest row that actually carries a weight. A check-in recording only
  /// a waist measurement must not blank out the weight the app reads.
  Stream<CheckInRow?> watchLatestWeight() {
    return (select(checkIns)
          ..where((row) => row.deletedAt.isNull() & row.weightKg.isNotNull())
          ..orderBy([(row) => OrderingTerm.desc(row.date)])
          ..limit(1))
        .watchSingleOrNull();
  }

  Future<CheckInRow?> findByDate(String date) {
    return (select(checkIns)
          ..where((row) => row.date.equals(date) & row.deletedAt.isNull()))
        .getSingleOrNull();
  }

  /// One row per date. Weighing yourself twice in a morning is a correction,
  /// not a second data point on the trend.
  Future<CheckInRow> upsert({
    required String date,
    double? weightKg,
    double? waistCm,
    String? programId,
    String? phaseId,
    String? notes,
  }) async {
    return transaction(() async {
      final existing = await findByDate(date);

      if (existing != null) {
        await (update(
          checkIns,
        )..where((row) => row.id.equals(existing.id))).write(
          CheckInsCompanion(
            weightKg: Value(weightKg),
            waistCm: Value(waistCm),
            programId: Value(programId),
            phaseId: Value(phaseId),
            notes: Value(notes),
            updatedAt: Value(DateTime.now()),
            syncState: const Value(SyncState.pendingUpdate),
          ),
        );
        return (select(
          checkIns,
        )..where((row) => row.id.equals(existing.id))).getSingle();
      }

      return into(checkIns).insertReturning(
        CheckInsCompanion.insert(
          date: date,
          weightKg: Value(weightKg),
          waistCm: Value(waistCm),
          programId: Value(programId),
          phaseId: Value(phaseId),
          notes: Value(notes),
        ),
      );
    });
  }

  /// Soft delete, like everything else — a hard one could not propagate to
  /// another device (ADR §6.2 rule 5).
  Future<void> softDelete(String id) async {
    final now = DateTime.now();
    await (update(checkIns)..where((row) => row.id.equals(id))).write(
      CheckInsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        syncState: const Value(SyncState.pendingDelete),
      ),
    );
  }
}
