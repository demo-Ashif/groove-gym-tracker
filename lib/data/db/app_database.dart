import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/logging/app_logger.dart';
import '../../domain/enums/training_enums.dart';
import 'daos/check_in_dao.dart';
import 'daos/exercise_dao.dart';
import 'daos/insights_dao.dart';
import 'daos/log_dao.dart';
import 'daos/plan_dao.dart';
import 'daos/schedule_dao.dart';
import 'migrations.dart';
import 'pre_migration_snapshot.dart';
import 'seed/exercise_seed.dart';
import 'tables/catalog_tables.dart';
import 'tables/check_in_tables.dart';
import 'tables/log_tables.dart';
import 'tables/plan_tables.dart';
// The generated part file calls `newRowId` for every table's client default,
// and a part shares its library's imports — so this one is load-bearing even
// though nothing in this file names it directly.
import 'tables/sync_columns.dart';
import 'tables/sync_tables.dart';

part 'app_database.g.dart';

/// Fixed namespace for deriving **deterministic ids for seeded system rows**.
///
/// This is the decision that makes a shared catalog work across devices. A
/// random id per install would mean this phone's "Back squat" and the next
/// one's are different rows, so ten weeks of squat history would refuse to
/// merge and the server would accumulate a duplicate catalog per device.
/// A v5 id is a hash of (namespace, name_key), so every device — and
/// `supabase/seed.sql` — independently derives the *same* id for the same
/// exercise, and pushing the catalog is idempotent.
///
/// Never change this value. It is effectively part of the schema.
const _systemIdNamespace = 'a4f1c0de-2a1b-4c33-9f6e-8d5b1c7a90e2';

const _uuid = Uuid();

/// The id a seeded exercise has on every device, forever.
String systemExerciseId(String nameKey) =>
    _uuid.v5(_systemIdNamespace, nameKey);

@DriftDatabase(
  tables: [
    Exercises,
    Programs,
    Phases,
    SessionTemplates,
    BlockTemplates,
    ExerciseTemplates,
    ScheduledSessions,
    SessionLogs,
    SetLogs,
    Prs,
    CheckIns,
    MetricDefinitions,
    SyncOutbox,
  ],
  daos: [CheckInDao, ExerciseDao, InsightsDao, LogDao, PlanDao, ScheduleDao],
)
class AppDatabase extends _$AppDatabase {
  /// Production: opens `groove.sqlite` in the app's documents directory, on a
  /// background isolate so a set write never competes with the frame the user
  /// is looking at.
  AppDatabase() : snapshotSink = null, super(driftDatabase(name: 'groove'));

  /// For tests and migration checks — pass `NativeDatabase.memory()`.
  ///
  /// [snapshotSink] redirects the pre-migration backup away from the real
  /// documents directory, which is also the seam a migration test uses to
  /// assert that the backup was taken at all.
  AppDatabase.withExecutor(super.executor, {this.snapshotSink});

  /// Where the pre-migration backup is written. Null means the app's own
  /// documents directory.
  final SnapshotSink? snapshotSink;

  /// Bump only alongside a step in [AppMigrations] **and** a test that walks
  /// data from the previous version through it. A bad migration is the one bug
  /// that destroys history (ADR §17.2).
  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _seedCatalog();
    },
    onUpgrade: (m, from, to) async {
      AppLogger.i('Schema upgrade $from -> $to', tag: 'DB');

      // The whole database goes to a JSON file first. Migrations here are
      // non-destructive by contract, but they rewrite the only copy of the
      // user's training that exists — so there is an undo on disk before a
      // single table is touched.
      await PreMigrationSnapshot(
        this,
        sink: snapshotSink,
      ).capture(fromVersion: from, toVersion: to);

      await AppMigrations.apply(this, m, from, to);

      // Idempotent, keyed on deterministic ids: a release that adds catalog
      // exercises gets them here, and everything already present is left
      // exactly as the user edited it.
      await _seedCatalog();
    },
    beforeOpen: (details) async {
      // Off by default in SQLite, and everything in this schema leans on it:
      // cascade deletes, and the `restrict` that stops a catalog row being
      // deleted out from under ten weeks of set logs.
      await customStatement('PRAGMA foreign_keys = ON');

      if (details.wasCreated) {
        AppLogger.i(
          'Created schema v${details.versionNow} with '
          '${exerciseCatalogSeed.length} catalog exercises',
          tag: 'DB',
        );
      }
    },
  );

  /// Writes the system catalog in one transaction, so a crash mid-seed leaves
  /// no half-populated catalog behind.
  ///
  /// `insertOnConflictUpdate` on a deterministic id makes this re-runnable:
  /// a future release that adds exercises can call it again and only the new
  /// rows land.
  Future<void> _seedCatalog() async {
    await transaction(() async {
      await batch((batch) {
        for (final exercise in exerciseCatalogSeed) {
          batch.insert(
            exercises,
            ExercisesCompanion.insert(
              id: Value(systemExerciseId(exercise.nameKey)),
              nameKey: Value(exercise.nameKey),
              aliases: Value(jsonEncode(exercise.aliases)),
              pattern: exercise.pattern,
              // Derived once, at seed time, from the pattern and muscles the
              // seed already carries — rather than hand-tagging 123 rows and
              // letting them drift out of step with their own muscle lists.
              bodySection: BodySection.forExercise(
                pattern: exercise.pattern,
                primaryMuscles: exercise.primaryMuscles,
              ),
              loadType: exercise.loadType,
              isUnilateral: Value(exercise.isUnilateral),
              primaryMuscles: Value(jsonEncode(exercise.primaryMuscles)),
              isSystem: const Value(true),
              // Seeded rows are not this device's news to tell: the server
              // gets the identical catalog from `supabase/seed.sql`, derived
              // from the same name keys through the same v5 namespace. Marking
              // them pending would push 122 rows on first launch to no effect.
              syncState: const Value(SyncState.synced),
            ),
            mode: InsertMode.insertOrReplace,
          );
        }
      });
    });
  }
}
