import 'dart:convert';

// `isNull`/`isNotNull` exist in both drift (column predicates) and matcher
// (test expectations). The matchers are what this file wants.
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:groove/data/db/app_database.dart';
import 'package:groove/data/db/seed/exercise_seed.dart';
import 'package:groove/domain/enums/training_enums.dart';

/// Schema-level tests against a real in-memory SQLite, not a fake.
///
/// These exist because the database is the source of truth (ADR §2.1
/// principle 3): a constraint that doesn't actually fire is a constraint that
/// isn't there, and the only way to know is to make SQLite refuse the write.
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  group('schema creation', () {
    test('creates v1 and seeds the full catalog', () async {
      expect(db.schemaVersion, 1);
      expect(await db.exerciseDao.countActive(), exerciseCatalogSeed.length);
    });

    test('every seeded row is a system row with a name key and no literal '
        'name', () async {
      final rows = await db.select(db.exercises).get();

      expect(rows, hasLength(exerciseCatalogSeed.length));
      for (final row in rows) {
        expect(row.isSystem, isTrue, reason: row.id);
        expect(row.nameKey, isNotNull, reason: row.id);
        expect(row.customName, isNull, reason: row.id);
        // Seeded rows are not this device's news to tell — the server gets an
        // identical catalog from seed.sql.
        expect(row.syncState, SyncState.synced, reason: row.id);
      }
    });

    test('seeded ids are deterministic, so two devices agree on what a '
        'squat is', () async {
      final backSquat = await db.exerciseDao.findById(
        systemExerciseId('exBackSquat'),
      );

      expect(backSquat, isNotNull);
      expect(backSquat!.nameKey, 'exBackSquat');
      expect(backSquat.pattern, MovementPattern.squat);

      // Same input, same id, on any device and in seed.sql.
      expect(systemExerciseId('exBackSquat'), systemExerciseId('exBackSquat'));
      expect(
        systemExerciseId('exBackSquat'),
        isNot(systemExerciseId('exFrontSquat')),
      );
    });

    test('seeding again is idempotent — a later release can add rows without '
        'duplicating the catalog', () async {
      final before = await db.exerciseDao.countActive();

      // Re-running the seed is what a schema upgrade will do.
      await db
          .into(db.exercises)
          .insert(
            ExercisesCompanion.insert(
              id: Value(systemExerciseId('exBackSquat')),
              nameKey: const Value('exBackSquat'),
              pattern: MovementPattern.squat,
              loadType: LoadType.barbell,
              isSystem: const Value(true),
            ),
            mode: InsertMode.insertOrReplace,
          );

      expect(await db.exerciseDao.countActive(), before);
    });

    test('JSON columns round-trip', () async {
      final rdl = await db.exerciseDao.findById(
        systemExerciseId('exRomanianDeadlift'),
      );

      expect(jsonDecode(rdl!.aliases), contains('RDL'));
      expect(jsonDecode(rdl.primaryMuscles), contains('hamstrings'));
    });
  });

  group('constraints', () {
    test('an exercise must have exactly one name source', () async {
      Future<void> insert({String? nameKey, String? customName}) {
        return db
            .into(db.exercises)
            .insert(
              ExercisesCompanion.insert(
                nameKey: Value(nameKey),
                customName: Value(customName),
                pattern: MovementPattern.squat,
                loadType: LoadType.barbell,
              ),
            );
      }

      // Neither: would render as blank text in a chart legend months later.
      await expectLater(insert(), throwsA(isA<SqliteException>()));
      // Both: ambiguous — which one wins at render time?
      await expectLater(
        insert(nameKey: 'exBackSquat', customName: 'Back squat'),
        throwsA(isA<SqliteException>()),
      );
      // Exactly one: fine.
      await insert(customName: 'Zercher squat');
    });

    test('a skipped set must carry a reason, and a completed one must '
        'not', () async {
      final ids = await _seedSessionWithOneExercise(db);

      Future<void> insertSet({required SetStatus status, SkipReason? reason}) {
        return db
            .into(db.setLogs)
            .insert(
              SetLogsCompanion.insert(
                sessionLogId: ids.sessionLogId,
                exerciseId: ids.exerciseId,
                setIndex: 0,
                status: Value(status),
                skipReason: Value(reason),
              ),
            );
      }

      // A silent gap is guilt; a reason is data (ADR §20.1 item 7).
      await expectLater(
        insertSet(status: SetStatus.skipped),
        throwsA(isA<SqliteException>()),
      );
      await expectLater(
        insertSet(status: SetStatus.done, reason: SkipReason.pain),
        throwsA(isA<SqliteException>()),
      );
      await insertSet(status: SetStatus.skipped, reason: SkipReason.pain);
    });

    test('foreign keys are enforced — a set cannot point at a missing '
        'exercise', () async {
      final ids = await _seedSessionWithOneExercise(db);

      await expectLater(
        db
            .into(db.setLogs)
            .insert(
              SetLogsCompanion.insert(
                sessionLogId: ids.sessionLogId,
                exerciseId: 'no-such-exercise',
                setIndex: 0,
              ),
            ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('a catalog row cannot be hard-deleted out from under its set '
        'logs', () async {
      final ids = await _seedSessionWithOneExercise(db);
      await db
          .into(db.setLogs)
          .insert(
            SetLogsCompanion.insert(
              sessionLogId: ids.sessionLogId,
              exerciseId: ids.exerciseId,
              setIndex: 0,
              reps: const Value(8),
              weightKg: const Value(60),
            ),
          );

      // `restrict`, not `cascade`: ten weeks of history must not vanish
      // because someone tidied the catalog.
      await expectLater(
        (db.delete(
          db.exercises,
        )..where((r) => r.id.equals(ids.exerciseId))).go(),
        throwsA(isA<SqliteException>()),
      );

      // The supported way to remove it.
      await db.exerciseDao.hide(ids.exerciseId);
      final hidden = await db.exerciseDao.findById(ids.exerciseId);
      expect(hidden!.deletedAt, isNotNull);
      expect(hidden.syncState, SyncState.pendingDelete);
    });

    test('deleting a session log cascades to its sets', () async {
      final ids = await _seedSessionWithOneExercise(db);
      await db
          .into(db.setLogs)
          .insert(
            SetLogsCompanion.insert(
              sessionLogId: ids.sessionLogId,
              exerciseId: ids.exerciseId,
              setIndex: 0,
            ),
          );

      await (db.delete(
        db.sessionLogs,
      )..where((r) => r.id.equals(ids.sessionLogId))).go();

      expect(await db.select(db.setLogs).get(), isEmpty);
    });
  });

  group('catalog behaviour', () {
    test('hidden exercises leave the picker but stay resolvable', () async {
      final id = systemExerciseId('exBackSquat');

      await db.exerciseDao.hide(id);

      expect(
        await db.exerciseDao.countActive(),
        exerciseCatalogSeed.length - 1,
      );
      expect(await db.exerciseDao.findById(id), isNotNull);

      final catalog = await db.exerciseDao.watchCatalog().first;
      expect(catalog.map((e) => e.id), isNot(contains(id)));
    });

    test('a custom exercise stores literal text and is pending sync', () async {
      final id = await db.exerciseDao.createCustom(
        name: '  Zercher squat  ',
        pattern: MovementPattern.squat,
        loadType: LoadType.barbell,
      );

      final row = await db.exerciseDao.findById(id);
      expect(row!.customName, 'Zercher squat');
      expect(row.nameKey, isNull);
      expect(row.isSystem, isFalse);
      expect(row.syncState, SyncState.pendingCreate);
    });

    test('aliases are appended once, case-insensitively', () async {
      final id = systemExerciseId('exRomanianDeadlift');

      await db.exerciseDao.addAlias(id, 'stiff leg deadlift');
      await db.exerciseDao.addAlias(id, 'STIFF LEG DEADLIFT');
      await db.exerciseDao.addAlias(id, 'rdl');
      await db.exerciseDao.addAlias(id, '   ');

      final row = await db.exerciseDao.findById(id);
      final aliases = (jsonDecode(row!.aliases) as List).cast<String>();

      expect(
        aliases.where((a) => a.toLowerCase() == 'stiff leg deadlift'),
        hasLength(1),
      );
      // 'RDL' was already seeded; the lowercase form must not double it.
      expect(aliases.where((a) => a.toLowerCase() == 'rdl'), hasLength(1));
      expect(aliases, isNot(contains('')));
      expect(row.syncState, SyncState.pendingUpdate);
    });

    test(
      'alias search finds literal names and aliases, not ARB keys',
      () async {
        await db.exerciseDao.createCustom(
          name: 'Zercher squat',
          pattern: MovementPattern.squat,
          loadType: LoadType.barbell,
        );

        expect(await db.exerciseDao.findByText('zercher'), hasLength(1));
        expect(await db.exerciseDao.findByText('RDL'), hasLength(1));
        // `exBackSquat` is a key, not something a user types.
        expect(await db.exerciseDao.findByText('exBackSquat'), isEmpty);
      },
    );

    test('the catalog stream re-emits when a row is added', () async {
      final counts = <int>[];
      final subscription = db.exerciseDao.watchCatalog().listen(
        (rows) => counts.add(rows.length),
      );
      addTearDown(subscription.cancel);

      // The first emission has to land before the write, or the test races the
      // query and only ever sees the post-insert count.
      await pumpEventQueue();

      await db.exerciseDao.createCustom(
        name: 'Zercher squat',
        pattern: MovementPattern.squat,
        loadType: LoadType.barbell,
      );
      await pumpEventQueue();

      expect(counts, [
        exerciseCatalogSeed.length,
        exerciseCatalogSeed.length + 1,
      ]);
    });
  });

  group('row contract', () {
    test('ids are time-ordered, so inserts land at the right edge of the '
        'index', () async {
      final first = await db.exerciseDao.createCustom(
        name: 'First',
        pattern: MovementPattern.squat,
        loadType: LoadType.barbell,
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final second = await db.exerciseDao.createCustom(
        name: 'Second',
        pattern: MovementPattern.squat,
        loadType: LoadType.barbell,
      );

      expect(first.compareTo(second), lessThan(0));
    });

    test('timestamps and defaults are stamped without the caller', () async {
      final id = await db.exerciseDao.createCustom(
        name: 'Zercher squat',
        pattern: MovementPattern.squat,
        loadType: LoadType.barbell,
      );

      final row = await db.exerciseDao.findById(id);
      expect(row!.createdAt, isNotNull);
      expect(row.updatedAt, isNotNull);
      expect(row.deletedAt, isNull);
      expect(row.schemaVersion, 1);
      // Null until the first anonymous sign-in; the app is fully usable
      // before any backend exists.
      expect(row.ownerId, isNull);
    });
  });
}

/// Minimal program → phase → template → scheduled session → session log
/// chain, for the tests that need a set to hang off something real.
Future<({String exerciseId, String sessionLogId})> _seedSessionWithOneExercise(
  AppDatabase db,
) async {
  final program = await db
      .into(db.programs)
      .insertReturning(
        ProgramsCompanion.insert(name: 'Test block', startDate: '2026-08-16'),
      );

  final scheduled = await db
      .into(db.scheduledSessions)
      .insertReturning(
        ScheduledSessionsCompanion.insert(
          programId: program.id,
          date: '2026-08-16',
          weekNumber: 1,
          kind: ScheduledSessionKind.gym,
        ),
      );

  final log = await db
      .into(db.sessionLogs)
      .insertReturning(
        SessionLogsCompanion.insert(
          scheduledSessionId: scheduled.id,
          startedAt: DateTime(2026, 8, 16, 18),
        ),
      );

  return (exerciseId: systemExerciseId('exBackSquat'), sessionLogId: log.id);
}
