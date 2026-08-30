import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:groove/data/db/app_database.dart';
import 'package:groove/data/db/migrations.dart';
import 'package:groove/domain/enums/training_enums.dart';
import 'package:sqlite3/sqlite3.dart';

/// Migrations, tested the only way that means anything: build the **old**
/// database, put real rows in it, run the upgrade, and check the rows are
/// still there and still say the same thing.
///
/// A migration is the one change that can destroy a user's history, and it is
/// invisible until it has already happened on their phone.
void main() {
  late Directory tempDir;
  late File dbFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('groove_migration');
    dbFile = File('${tempDir.path}/groove.sqlite');
  });

  tearDown(() async {
    if (tempDir.existsSync()) await tempDir.delete(recursive: true);
  });

  /// The exact DDL v1 shipped with, plus a program's worth of rows.
  void seedVersion1() {
    final raw = sqlite3.open(dbFile.path);
    try {
      final fixture = File('test/data/fixtures/schema_v1.sql').readAsStringSync();
      for (final statement in fixture.split(';\n')) {
        if (statement.trim().isEmpty) continue;
        raw.execute(statement);
      }

      const now = '2026-08-16T09:00:00.000';

      // A seeded catalog row and one the user typed themselves. Both need a
      // body section deriving; only the second can prove the user's own words
      // survived.
      raw.execute('''
INSERT INTO exercises (id, created_at, updated_at, sync_state, name_key, aliases,
  pattern, load_type, is_unilateral, primary_muscles, is_system)
VALUES ('ex-rdl', '$now', '$now', 'synced', 'exRomanianDeadlift', '[]',
  'hinge', 'barbell', 0, '["hamstrings","glutes"]', 1)''');
      raw.execute('''
INSERT INTO exercises (id, created_at, updated_at, sync_state, custom_name, aliases,
  pattern, load_type, is_unilateral, primary_muscles, is_system)
VALUES ('ex-custom', '$now', '$now', 'pendingCreate', 'Gym-specific press', '[]',
  'push', 'machine', 0, '["chest"]', 0)''');

      raw.execute('''
INSERT INTO programs (id, created_at, updated_at, sync_state, name, start_date, is_active)
VALUES ('prog-1', '$now', '$now', 'synced', 'Block 1', '2026-08-17', 1)''');
      raw.execute('''
INSERT INTO phases (id, created_at, updated_at, sync_state, program_id, name,
  order_index, start_week, end_week, check_in_due_at_end)
VALUES ('phase-1', '$now', '$now', 'synced', 'prog-1', 'Cycle 1', 0, 1, 3, 1)''');
      raw.execute('''
INSERT INTO session_templates (id, created_at, updated_at, sync_state, phase_id,
  code, title, order_index)
VALUES ('sess-1', '$now', '$now', 'synced', 'phase-1', 'A', 'Push', 0)''');
      raw.execute('''
INSERT INTO block_templates (id, created_at, updated_at, sync_state,
  session_template_id, kind, title, order_index)
VALUES ('block-1', '$now', '$now', 'synced', 'sess-1', 'main', 'Main', 0)''');

      // A range, a max-only prescription, and one with neither — all three
      // shapes v1 allowed.
      raw.execute('''
INSERT INTO exercise_templates (id, created_at, updated_at, sync_state,
  block_template_id, exercise_id, order_index, target_sets, target_reps_min,
  target_reps_max, target_load_kg, rest_seconds, per_side)
VALUES ('tmpl-range', '$now', '$now', 'synced', 'block-1', 'ex-rdl', 0, 4, 8, 12, 60, 90, 0)''');
      raw.execute('''
INSERT INTO exercise_templates (id, created_at, updated_at, sync_state,
  block_template_id, exercise_id, order_index, target_sets, target_reps_max,
  rest_seconds, per_side)
VALUES ('tmpl-max', '$now', '$now', 'synced', 'block-1', 'ex-custom', 1, 3, 15, 90, 0)''');
      raw.execute('''
INSERT INTO exercise_templates (id, created_at, updated_at, sync_state,
  block_template_id, exercise_id, order_index, target_sets, rest_seconds, per_side)
VALUES ('tmpl-open', '$now', '$now', 'synced', 'block-1', 'ex-rdl', 2, 5, 90, 0)''');

      raw.execute('''
INSERT INTO scheduled_sessions (id, created_at, updated_at, sync_state, program_id,
  session_template_id, date, week_number, kind, status)
VALUES ('day-1', '$now', '$now', 'synced', 'prog-1', 'sess-1', '2026-08-17', 1,
  'gym', 'completed')''');

      raw.execute('''
INSERT INTO session_logs (id, created_at, updated_at, sync_state,
  scheduled_session_id, started_at, ended_at, session_rpe)
VALUES ('log-1', '$now', '$now', 'synced', 'day-1', '$now', '2026-08-16T10:20:00.000', 8.0)''');
      raw.execute('''
INSERT INTO set_logs (id, created_at, updated_at, sync_state, session_log_id,
  exercise_id, set_index, side, status, reps, weight_kg, is_pr)
VALUES ('set-1', '$now', '$now', 'synced', 'log-1', 'ex-rdl', 0, 'both', 'done',
  8, 100.0, 0)''');

      raw.execute('''
INSERT INTO check_ins (id, created_at, updated_at, sync_state, date, weight_kg)
VALUES ('checkin-1', '$now', '$now', 'synced', '2026-08-16', 84.5)''');

      raw.execute('PRAGMA user_version = 1');
    } finally {
      raw.close();
    }
  }

  /// Opens the v1 file with the current build, which runs the migration.
  AppDatabase openCurrent({Map<String, String>? snapshots}) {
    return AppDatabase.withExecutor(
      NativeDatabase(dbFile),
      snapshotSink: snapshots == null
          ? null
          : (name, contents) async => snapshots[name] = contents,
    );
  }

  test('v1 data survives the upgrade to v2 intact', () async {
    seedVersion1();
    final db = openCurrent();
    addTearDown(db.close);

    // Opening runs the migration.
    final version = await db
        .customSelect('PRAGMA user_version')
        .getSingle();
    expect(version.data.values.first, 2);

    final exercises = await db.select(db.exercises).get();
    final custom = exercises.firstWhere((row) => row.id == 'ex-custom');
    final rdl = exercises.firstWhere((row) => row.id == 'ex-rdl');

    // The user's own words are untouched, and the new column was derived
    // rather than left on its placeholder.
    expect(custom.customName, 'Gym-specific press');
    expect(custom.bodySection, BodySection.chest);
    expect(rdl.bodySection, BodySection.legs);

    final templates = await db.select(db.exerciseTemplates).get();
    final byId = {for (final row in templates) row.id: row};

    // A range collapses to its lower end, a max-only row keeps its number, and
    // a prescription that never had reps still has none.
    expect(byId['tmpl-range']!.targetReps, 8);
    expect(byId['tmpl-range']!.targetLoadKg, 60);
    expect(byId['tmpl-max']!.targetReps, 15);
    expect(byId['tmpl-open']!.targetReps, isNull);
    expect(byId['tmpl-open']!.targetDurationSec, isNull);
    expect(byId['tmpl-range']!.targetSets, 4);

    // Nothing else lost a row.
    expect(await db.select(db.programs).get(), hasLength(1));
    expect(await db.select(db.phases).get(), hasLength(1));
    expect(await db.select(db.sessionTemplates).get(), hasLength(1));
    expect(await db.select(db.blockTemplates).get(), hasLength(1));
    expect(await db.select(db.scheduledSessions).get(), hasLength(1));
    expect(await db.select(db.sessionLogs).get(), hasLength(1));

    final sets = await db.select(db.setLogs).get();
    expect(sets.single.weightKg, 100);
    expect(sets.single.reps, 8);

    final checkIns = await db.select(db.checkIns).get();
    expect(checkIns.single.weightKg, 84.5);
  });

  test('the upgrade seeds the catalog without touching existing rows', () async {
    seedVersion1();
    final db = openCurrent();
    addTearDown(db.close);

    final exercises = await db.select(db.exercises).get();

    // The seeded catalog arrives, the user's own row is still exactly one row,
    // and the v1 row that shared a seeded id was updated rather than doubled.
    expect(exercises.length, greaterThan(100));
    expect(
      exercises.where((row) => row.customName == 'Gym-specific press'),
      hasLength(1),
    );
    expect(exercises.where((row) => row.id == 'ex-rdl'), hasLength(1));
  });

  test('a scheduled day can lose its program after the upgrade', () async {
    seedVersion1();
    final db = openCurrent();
    addTearDown(db.close);

    // v1 declared `program_id` NOT NULL. If the rewrite had not relaxed it,
    // this insert would throw — which is the backfill path in ADR §8.2.
    await db
        .into(db.scheduledSessions)
        .insert(
          ScheduledSessionsCompanion.insert(
            date: '2026-07-01',
            weekNumber: 0,
            kind: ScheduledSessionKind.gym,
          ),
        );

    final days = await db.select(db.scheduledSessions).get();
    expect(days, hasLength(2));
    expect(days.where((row) => row.programId == null), hasLength(1));
  });

  test('every row is backed up to a snapshot before anything is rewritten', () async {
    seedVersion1();
    final snapshots = <String, String>{};
    final db = openCurrent(snapshots: snapshots);
    addTearDown(db.close);

    // Force the open, and with it the migration.
    await db.select(db.programs).get();

    expect(snapshots, hasLength(1));
    final payload = jsonDecode(snapshots.values.single) as Map<String, Object?>;

    expect(payload['schemaVersion'], 1);
    expect(payload['upgradingTo'], 2);

    final tables = payload['tables']! as Map<String, Object?>;
    final templates = tables['exercise_templates']! as List<Object?>;
    final range = templates.firstWhere(
          (row) => (row! as Map<String, Object?>)['id'] == 'tmpl-range',
        )!
        as Map<String, Object?>;

    // The snapshot holds the *old* shape — the columns the migration is about
    // to drop. That is the entire point of taking it.
    expect(range['target_reps_min'], 8);
    expect(range['target_reps_max'], 12);
    expect((tables['set_logs']! as List<Object?>), hasLength(1));
  });

  test('a fresh database is created at the current version, never migrated', () async {
    final snapshots = <String, String>{};
    final db = openCurrent(snapshots: snapshots);
    addTearDown(db.close);

    final exercises = await db.select(db.exercises).get();
    expect(exercises.length, greaterThan(100));
    // Nothing to back up: there was no database before this one.
    expect(snapshots, isEmpty);
  });

  test('an unknown schema version refuses to migrate rather than guessing', () async {
    final db = AppDatabase.withExecutor(NativeDatabase.memory());
    addTearDown(db.close);
    await db.select(db.programs).get();

    // A build that has no step for the version on disk must leave the disk
    // alone — the next build can still migrate it. Dropping tables here is
    // what this whole file exists to prevent.
    await expectLater(
      AppMigrations.apply(db, db.createMigrator(), 5, 6),
      throwsStateError,
    );
  });
}
