import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:groove/core/error/app_exception.dart';
import 'package:groove/data/backup/backup_service.dart';
import 'package:groove/data/db/app_database.dart';
import 'package:groove/data/repositories/log_repository_impl.dart';
import 'package:groove/data/repositories/plan_repository_impl.dart';
import 'package:groove/data/repositories/schedule_repository_impl.dart';
import 'package:groove/domain/enums/training_enums.dart';
import 'package:groove/domain/values/calendar_date.dart';
import 'package:groove/domain/values/schedule_pattern.dart';

/// The export is the only copy of a user's training that cannot be broken from
/// the server end, so its round trip is worth checking properly.
void main() {
  // A round trip needs two databases: the one that was exported and the one
  // restored into. They have separate in-memory executors, so drift's warning
  // about a shared one does not apply here.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late BackupService backup;

  const start = CalendarDate(2026, 8, 16);
  final squat = systemExerciseId('exBackSquat');

  setUp(() {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    backup = BackupService(db);
  });

  tearDown(() => db.close());

  /// A program, a schedule and a logged session — one of everything that
  /// matters.
  Future<void> seedTraining() async {
    final plan = PlanRepositoryImpl(db.planDao);
    final schedule = ScheduleRepositoryImpl(
      dao: db.scheduleDao,
      planRepository: plan,
      now: () => DateTime(2026, 8, 16, 9),
    );
    final log = LogRepositoryImpl(db.logDao);

    final program = (await plan.createProgram(
      name: 'Ten week block',
      startDate: start,
    )).dataOrNull!;
    final phase = (await plan.addPhase(
      programId: program.id,
      name: 'Cycle 1',
      startWeek: 1,
      endWeek: 1,
    )).dataOrNull!;
    final session = (await plan.addSession(
      phaseId: phase.id,
      code: 'A',
      title: 'Push',
    )).dataOrNull!;
    final block = (await plan.addBlock(
      sessionTemplateId: session.id,
      kind: BlockKind.main,
      title: 'Main',
    )).dataOrNull!;
    await plan.addExercise(
      blockTemplateId: block.id,
      exerciseId: squat,
      targetSets: 4,
      targetRepsMin: 8,
      targetRepsMax: 8,
    );
    await schedule.commitSchedule(
      programId: program.id,
      pattern: SchedulePattern.weekly({
        DateTime.sunday: const DayAssignment.gym('A'),
      }),
    );

    final day = (await schedule.watchProgramSchedule(program.id).first)
        .firstWhere((d) => d.kind == ScheduledSessionKind.gym);
    final sessionLog = (await log.startSession(
      scheduledSessionId: day.id,
    )).dataOrNull!;
    await log.logSet(
      sessionLogId: sessionLog.id,
      exerciseId: squat,
      setIndex: 0,
      reps: 8,
      weightKg: 102.5,
      rpe: 7.5,
    );
    await log.finalizeSession(
      sessionLogId: sessionLog.id,
      scheduledSessionId: day.id,
      plannedSets: 4,
    );
  }

  group('export', () {
    test('writes a versioned, readable dump', () async {
      await seedTraining();

      final json = jsonDecode(await backup.export()) as Map<String, Object?>;

      expect(json['formatVersion'], BackupService.formatVersion);
      expect(json['schemaVersion'], db.schemaVersion);
      expect(DateTime.tryParse('${json['exportedAt']}'), isNotNull);

      final tables = json['tables']! as Map<String, Object?>;
      // The catalog, the plan and the log all travel.
      expect((tables['exercises']! as List), hasLength(122));
      expect((tables['programs']! as List), hasLength(1));
      expect((tables['set_logs']! as List), hasLength(1));
    });

    test('leaves the outbox out', () async {
      final json = jsonDecode(await backup.export()) as Map<String, Object?>;
      final tables = json['tables']! as Map<String, Object?>;

      // One device's queue of unsent intent is not data, and replaying it on
      // another device would repeat writes that already happened.
      expect(tables.containsKey('sync_outbox'), isFalse);
    });
  });

  group('round trip', () {
    test('restores everything it exported, ids included', () async {
      await seedTraining();
      final json = await backup.export();

      final before = await db.select(db.setLogs).get();

      // Wipe by restoring into a database that has only the seeded catalog.
      final fresh = AppDatabase.withExecutor(NativeDatabase.memory());
      addTearDown(fresh.close);
      final restored = await BackupService(fresh).restore(json);

      expect(restored, greaterThan(122));

      final after = await fresh.select(fresh.setLogs).get();
      expect(after, hasLength(before.length));
      // Same ids: a restore has to agree with whatever the server already has.
      expect(after.single.id, before.single.id);
      expect(after.single.weightKg, 102.5);
      expect(after.single.rpe, 7.5);

      final programs = await fresh.select(fresh.programs).get();
      expect(programs.single.name, 'Ten week block');
      expect(programs.single.schedulePattern, isNotNull);
    });

    test('typed columns survive JSON', () async {
      await seedTraining();
      final fresh = AppDatabase.withExecutor(NativeDatabase.memory());
      addTearDown(fresh.close);

      await BackupService(fresh).restore(await backup.export());

      final program = (await fresh.select(fresh.programs).get()).single;
      final template =
          (await fresh.select(fresh.exerciseTemplates).get()).single;
      final day = (await fresh.select(fresh.scheduledSessions).get()).first;

      // bool, int, double, enum and date-as-text all come back as themselves
      // rather than as strings.
      expect(program.isActive, isA<bool>());
      expect(template.targetSets, 4);
      expect(template.perSide, isFalse);
      expect(day.kind, isA<ScheduledSessionKind>());
      expect(day.date, hasLength(10));
    });

    test('restoring twice is idempotent', () async {
      await seedTraining();
      final json = await backup.export();

      final fresh = AppDatabase.withExecutor(NativeDatabase.memory());
      addTearDown(fresh.close);

      await BackupService(fresh).restore(json);
      await BackupService(fresh).restore(json);

      expect(await fresh.select(fresh.setLogs).get(), hasLength(1));
      expect(await fresh.select(fresh.programs).get(), hasLength(1));
    });

    test('restoring replaces rather than merges', () async {
      await seedTraining();
      final json = await backup.export();

      final other = AppDatabase.withExecutor(NativeDatabase.memory());
      addTearDown(other.close);
      // A program that is not in the backup must not survive the restore.
      final otherPlan = PlanRepositoryImpl(other.planDao);
      await otherPlan.createProgram(name: 'Local only', startDate: start);

      await BackupService(other).restore(json);

      final programs = await other.select(other.programs).get();
      expect(programs, hasLength(1));
      expect(programs.single.name, 'Ten week block');
    });
  });

  group('preview', () {
    test('reports what a file holds without writing', () async {
      await seedTraining();
      final json = await backup.export();

      final other = AppDatabase.withExecutor(NativeDatabase.memory());
      addTearDown(other.close);
      final service = BackupService(other);

      final preview = service.preview(json);

      expect(preview.schemaVersion, db.schemaVersion);
      expect(preview.exportedAt, isNotNull);
      expect(preview.rowCounts['programs'], 1);
      expect(preview.totalRows, greaterThan(122));

      // Nothing was written.
      expect(await other.select(other.programs).get(), isEmpty);
    });
  });

  group('bad input', () {
    test('rejects nonsense before touching the database', () async {
      await seedTraining();
      final rowsBefore = await db.select(db.programs).get();

      for (final bad in ['not json', '[]', '{}', '{"tables": 5}']) {
        expect(
          () => backup.preview(bad),
          throwsA(isA<ParseException>()),
          reason: bad,
        );
      }

      await expectLater(
        backup.restore('not json'),
        throwsA(isA<ParseException>()),
      );
      expect(await db.select(db.programs).get(), hasLength(rowsBefore.length));
    });

    test('refuses a backup from a newer version', () async {
      final json = jsonEncode({
        'formatVersion': 1,
        'schemaVersion': 99,
        'tables': <String, Object?>{},
      });

      // Guessing at columns this build doesn't know would drop data silently.
      await expectLater(backup.restore(json), throwsA(isA<ParseException>()));
    });

    test('a failed restore leaves the database as it was', () async {
      await seedTraining();
      final before = await db.select(db.programs).get();

      // Valid JSON, valid shape, but a row that violates a foreign key.
      final json = jsonEncode({
        'formatVersion': 1,
        'schemaVersion': db.schemaVersion,
        'tables': {
          'programs': [
            {'id': 'p1', 'name': 'Broken', 'start_date': '2026-08-16'},
          ],
          'phases': [
            {
              'id': 'ph1',
              'program_id': 'does-not-exist',
              'name': 'Orphan',
              'order_index': 0,
              'start_week': 1,
              'end_week': 2,
            },
          ],
        },
      });

      await expectLater(backup.restore(json), throwsA(isA<Object>()));

      // All-or-nothing: a half-restored database is worse than either copy.
      final after = await db.select(db.programs).get();
      expect(after.map((p) => p.name), before.map((p) => p.name));
    });

    test('ignores columns this build does not know', () async {
      final json = jsonEncode({
        'formatVersion': 1,
        'schemaVersion': db.schemaVersion,
        'tables': {
          'programs': [
            {
              'id': 'p1',
              'name': 'From the future',
              'start_date': '2026-08-16',
              'a_column_that_does_not_exist': 'ignored',
            },
          ],
        },
      });

      final restored = await backup.restore(json);

      expect(restored, 1);
      final programs = await db.select(db.programs).get();
      expect(programs.single.name, 'From the future');
    });
  });
}
