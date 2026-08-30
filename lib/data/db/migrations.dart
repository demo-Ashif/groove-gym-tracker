import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/logging/app_logger.dart';
import '../../domain/enums/training_enums.dart';
import 'app_database.dart';

/// Every schema step the app knows how to take.
///
/// **The contract: a migration never destroys data.** No `drop`, no
/// `deleteOnSchemaChange`, no "pre-release reset" — in dev or in prod. A
/// device that has logged ten weeks of training is the only copy of that
/// training, and a schema change is not a reason to lose it.
///
/// Adding a version means three things, all of them non-optional:
///
/// 1. Bump [AppDatabase.schemaVersion].
/// 2. Add a `case` below that transforms the old shape into the new one,
///    preserving every row it can.
/// 3. Add a test in `test/data/migration_test.dart` that builds the *old*
///    schema from a fixture, puts rows in it, runs the upgrade, and asserts
///    the rows are still there and still mean the same thing.
///
/// An unknown version throws rather than guessing. Refusing to open leaves the
/// data on disk for the next build to migrate; guessing does not.
abstract final class AppMigrations {
  /// Applies every step between [from] and [to], one version at a time.
  ///
  /// Stepwise rather than jumping straight to the target: a device that skipped
  /// three releases must walk the same path as one that took them in order, or
  /// the intermediate transformations are silently never run.
  static Future<void> apply(
    AppDatabase db,
    Migrator m,
    int from,
    int to,
  ) async {
    for (var version = from; version < to; version++) {
      AppLogger.i('Migrating schema $version -> ${version + 1}', tag: 'DB');

      switch (version) {
        case 1:
          await _v1ToV2(db, m);
        default:
          throw StateError(
            'No migration from schema v$version. The database was left '
            'untouched — data is intact and this build cannot open it.',
          );
      }
    }
  }

  /// v1 → v2: the prescription model gained a single rep target and a time
  /// target, the catalog gained a body section, and a scheduled day no longer
  /// has to belong to a program (backfilled sessions, ADR §8.2).
  ///
  /// Every one of these is a table rewrite in SQLite — `ALTER TABLE` cannot
  /// drop a column, relax a `NOT NULL`, or add a non-null column without a
  /// default. `TableMigration` does the create-copy-swap, so the rows travel.
  static Future<void> _v1ToV2(AppDatabase db, Migrator m) async {
    // `body_section` is NOT NULL with no default, so every existing row needs
    // a value at the moment the column appears. A placeholder lands first and
    // the real value is derived immediately after — the alternative, a SQL
    // CASE mirroring `BodySection.forExercise`, would be a second copy of that
    // logic free to drift out of step with the first.
    await m.alterTable(
      TableMigration(
        db.exercises,
        newColumns: [db.exercises.bodySection],
        columnTransformer: {
          db.exercises.bodySection: const CustomExpression<String>(
            "'fullBody'",
          ),
        },
      ),
    );
    await _backfillBodySections(db);

    // A rep range collapses to the single target the app now prescribes.
    // Coalesce rather than pick a side: a v1 row could legitimately carry only
    // a maximum, and dropping it would quietly blank a prescription.
    await m.alterTable(
      TableMigration(
        db.exerciseTemplates,
        newColumns: [
          db.exerciseTemplates.targetReps,
          db.exerciseTemplates.targetDurationSec,
        ],
        columnTransformer: {
          db.exerciseTemplates.targetReps: const CustomExpression<int>(
            'COALESCE(target_reps_min, target_reps_max)',
          ),
        },
      ),
    );

    // `program_id` merely widens to nullable. No transformer: every column
    // copies across by name, and a widened constraint cannot reject a row that
    // already satisfied the stricter one.
    await m.alterTable(TableMigration(db.scheduledSessions));
  }

  /// Derives each exercise's body section from the pattern and muscles the row
  /// already carries — the same call the catalog seed makes.
  static Future<void> _backfillBodySections(AppDatabase db) async {
    final rows = await db
        .customSelect('SELECT id, pattern, primary_muscles FROM exercises')
        .get();

    await db.batch((batch) {
      for (final row in rows) {
        final pattern = _parsePattern(row.read<String>('pattern'));
        // An unreadable row keeps the placeholder rather than failing the
        // whole migration: a mis-filed exercise is a wrong group in a picker,
        // and a thrown migration is a user who cannot open the app.
        if (pattern == null) continue;

        batch.update(
          db.exercises,
          ExercisesCompanion(
            bodySection: Value(
              BodySection.forExercise(
                pattern: pattern,
                primaryMuscles: _parseMuscles(row.read<String>('primary_muscles')),
              ),
            ),
          ),
          where: (table) => table.id.equals(row.read<String>('id')),
        );
      }
    });
  }

  static MovementPattern? _parsePattern(String stored) {
    for (final pattern in MovementPattern.values) {
      if (pattern.name == stored) return pattern;
    }
    AppLogger.w('Unknown movement pattern during migration: $stored', tag: 'DB');
    return null;
  }

  static List<String> _parseMuscles(String stored) {
    try {
      final decoded = jsonDecode(stored);
      return [
        if (decoded is List)
          for (final muscle in decoded)
            if (muscle is String) muscle,
      ];
    } on FormatException {
      return const [];
    }
  }
}
