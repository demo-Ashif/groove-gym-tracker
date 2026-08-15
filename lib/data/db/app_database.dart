import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/logging/app_logger.dart';
import '../../domain/enums/training_enums.dart';
import 'daos/exercise_dao.dart';
import 'daos/log_dao.dart';
import 'daos/plan_dao.dart';
import 'daos/schedule_dao.dart';
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
  daos: [ExerciseDao, LogDao, PlanDao, ScheduleDao],
)
class AppDatabase extends _$AppDatabase {
  /// Production: opens `groove.sqlite` in the app's documents directory, on a
  /// background isolate so a set write never competes with the frame the user
  /// is looking at.
  AppDatabase() : super(driftDatabase(name: 'groove'));

  /// For tests and migration checks — pass `NativeDatabase.memory()`.
  AppDatabase.withExecutor(super.executor);

  /// Bump only alongside a `MigrationStrategy` step **and** a test that walks
  /// data from the previous version through it. A bad migration is the one bug
  /// that destroys history (ADR §17.2).
  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _seedCatalog();
    },
    onUpgrade: (m, from, to) async {
      // No steps yet — v1 is the first shipped schema. Each future step gets
      // its own `if (from < n)` block and its own test.
      AppLogger.i('Schema upgrade $from -> $to', tag: 'DB');
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
