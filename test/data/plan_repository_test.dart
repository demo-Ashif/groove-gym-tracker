import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:groove/core/error/failure.dart';
import 'package:groove/data/db/app_database.dart';
import 'package:groove/data/repositories/plan_repository_impl.dart';
import 'package:groove/domain/entities/plan.dart';
import 'package:groove/domain/enums/training_enums.dart';
import 'package:groove/domain/repositories/plan_repository.dart';
import 'package:groove/domain/values/calendar_date.dart';
import 'package:groove/domain/values/progression_rule.dart';

void main() {
  late AppDatabase db;
  late PlanRepository repository;

  const start = CalendarDate(2026, 8, 16);

  setUp(() {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    repository = PlanRepositoryImpl(db.planDao);
  });

  tearDown(() => db.close());

  Future<Program> newProgram([String name = 'Ten week block']) async {
    final result = await repository.createProgram(name: name, startDate: start);
    return result.dataOrNull!;
  }

  group('program', () {
    test('is created inactive and dated', () async {
      final program = await newProgram();

      expect(program.name, 'Ten week block');
      expect(program.startDate, start);
      expect(program.isActive, isFalse);
      expect(program.phases, isEmpty);
    });

    test('activating one deactivates the others', () async {
      final first = await newProgram('First');
      final second = await newProgram('Second');

      await repository.setActiveProgram(first.id);
      await repository.setActiveProgram(second.id);

      final programs = await repository.watchPrograms().first;
      final active = programs.where((p) => p.isActive).toList();

      // Two active programs would make "today's session" ambiguous.
      expect(active, hasLength(1));
      expect(active.single.id, second.id);
    });

    test('a deleted program leaves the list but keeps its rows', () async {
      final program = await newProgram();

      await repository.deleteProgram(program.id);

      expect(await repository.watchPrograms().first, isEmpty);
      // Soft delete: a hard one could not propagate to another device.
      expect((await repository.loadProgram(program.id)).dataOrNull, isNull);
      final raw = await db.planDao.findProgram(program.id);
      expect(raw, isNull, reason: 'reads filter deleted rows');
    });

    test('rejects an end date before the start', () async {
      final program = await newProgram();

      final result = await repository.updateProgram(
        Program(
          id: program.id,
          name: program.name,
          startDate: start,
          endDate: const CalendarDate(2026, 8, 1),
        ),
      );

      expect(result.failureOrNull, isA<ParseFailure>());
    });

    test('rejects a blank name', () async {
      final result = await repository.createProgram(
        name: '   ',
        startDate: start,
      );

      expect(result.failureOrNull, isA<ParseFailure>());
    });
  });

  group('tree assembly', () {
    test('loads a full program in one read, in order', () async {
      final program = await newProgram();
      await repository.setActiveProgram(program.id);

      final phase = (await repository.addPhase(
        programId: program.id,
        name: 'Cycle 1 — Foundation',
        startWeek: 1,
        endWeek: 3,
      )).dataOrNull!;

      final session = (await repository.addSession(
        phaseId: phase.id,
        code: 'A',
        title: 'Push + Core',
        dayOfWeek: DateTime.sunday,
      )).dataOrNull!;

      final warmup = (await repository.addBlock(
        sessionTemplateId: session.id,
        kind: BlockKind.warmup,
        title: 'Warm-up',
      )).dataOrNull!;

      final main = (await repository.addBlock(
        sessionTemplateId: session.id,
        kind: BlockKind.main,
        title: 'Main',
      )).dataOrNull!;

      await repository.addExercise(
        blockTemplateId: main.id,
        exerciseId: systemExerciseId('exLandminePress'),
        targetSets: 4,
        targetReps: 8,
        perSide: true,
        progression: const ProgressionRule.linearWeekly(incrementKg: 2.5),
      );

      final loaded = (await repository.loadProgram(program.id)).dataOrNull!;

      expect(loaded.phases, hasLength(1));
      expect(loaded.phases.single.sessions, hasLength(1));

      final blocks = loaded.phases.single.sessions.single.blocks;
      // Insertion order, via order_index — a warm-up must not sort after the
      // main block.
      expect(blocks.map((b) => b.id), [warmup.id, main.id]);
      expect(blocks.first.exercises, isEmpty);

      final prescribed = blocks.last.exercises.single;
      expect(prescribed.targetSets, 4);
      expect(prescribed.perSide, isTrue);
      expect(
        prescribed.progression,
        const ProgressionRule.linearWeekly(incrementKg: 2.5),
      );
      // 4 sets × 8 reps × 2 sides.
      expect(prescribed.plannedReps, 64);
    });

    test('a phase with no sessions still appears', () async {
      final program = await newProgram();
      await repository.addPhase(
        programId: program.id,
        name: 'Empty phase',
        startWeek: 1,
        endWeek: 2,
      );

      final loaded = (await repository.loadProgram(program.id)).dataOrNull!;

      // The left join must not drop a parent because it has no children —
      // otherwise a phase disappears from the builder the moment its last
      // session is deleted.
      expect(loaded.phases, hasLength(1));
      expect(loaded.phases.single.sessions, isEmpty);
    });

    test(
      'the active program stream re-emits on a change four levels down',
      () async {
        final program = await newProgram();
        await repository.setActiveProgram(program.id);
        final phase = (await repository.addPhase(
          programId: program.id,
          name: 'Cycle 1',
          startWeek: 1,
          endWeek: 3,
        )).dataOrNull!;
        final session = (await repository.addSession(
          phaseId: phase.id,
          code: 'A',
          title: 'Push',
        )).dataOrNull!;
        final block = (await repository.addBlock(
          sessionTemplateId: session.id,
          kind: BlockKind.main,
          title: 'Main',
        )).dataOrNull!;

        final counts = <int>[];
        final subscription = repository.watchActiveProgram().listen((program) {
          counts.add(
            program
                    ?.phases
                    .single
                    .sessions
                    .single
                    .blocks
                    .single
                    .exercises
                    .length ??
                -1,
          );
        });
        addTearDown(subscription.cancel);
        await pumpEventQueue();

        await repository.addExercise(
          blockTemplateId: block.id,
          exerciseId: systemExerciseId('exBackSquat'),
          targetSets: 3,
        );
        await pumpEventQueue();

        expect(counts, [0, 1]);
      },
    );

    test('watchActiveProgram emits null when nothing is active', () async {
      await newProgram();

      expect(await repository.watchActiveProgram().first, isNull);
    });

    test('program week maths reads off the phases', () async {
      final program = await newProgram();
      await repository.addPhase(
        programId: program.id,
        name: 'Cycle 1',
        startWeek: 1,
        endWeek: 3,
      );
      await repository.addPhase(
        programId: program.id,
        name: 'Cycle 2',
        startWeek: 4,
        endWeek: 10,
      );

      final loaded = (await repository.loadProgram(program.id)).dataOrNull!;

      expect(loaded.weekCount, 10);
      expect(loaded.phaseForWeek(2)!.name, 'Cycle 1');
      expect(loaded.phaseForWeek(7)!.name, 'Cycle 2');
      expect(loaded.phaseForWeek(11), isNull);
    });
  });

  group('soft delete cascades', () {
    test('deleting a phase hides everything under it', () async {
      final program = await newProgram();
      final phase = (await repository.addPhase(
        programId: program.id,
        name: 'Cycle 1',
        startWeek: 1,
        endWeek: 3,
      )).dataOrNull!;
      final session = (await repository.addSession(
        phaseId: phase.id,
        code: 'A',
        title: 'Push',
      )).dataOrNull!;
      final block = (await repository.addBlock(
        sessionTemplateId: session.id,
        kind: BlockKind.main,
        title: 'Main',
      )).dataOrNull!;
      await repository.addExercise(
        blockTemplateId: block.id,
        exerciseId: systemExerciseId('exBackSquat'),
        targetSets: 3,
      );

      await repository.deletePhase(phase.id);

      // SQLite's ON DELETE CASCADE never fires for a soft delete, so the
      // repository has to walk the subtree itself. Half a hidden subtree is a
      // session that renders with no blocks.
      final rows = await db.planDao.loadPlan(program.id);
      expect(rows!.phases, isEmpty);
      expect(rows.sessions, isEmpty);
      expect(rows.blocks, isEmpty);
      expect(rows.exercises, isEmpty);

      final deletedExercises = await db.select(db.exerciseTemplates).get();
      expect(deletedExercises.single.deletedAt, isNotNull);
      expect(deletedExercises.single.syncState, SyncState.pendingDelete);
    });

    test(
      'deleting a block hides its exercise slots but not its siblings',
      () async {
        final program = await newProgram();
        final phase = (await repository.addPhase(
          programId: program.id,
          name: 'Cycle 1',
          startWeek: 1,
          endWeek: 3,
        )).dataOrNull!;
        final session = (await repository.addSession(
          phaseId: phase.id,
          code: 'A',
          title: 'Push',
        )).dataOrNull!;
        final first = (await repository.addBlock(
          sessionTemplateId: session.id,
          kind: BlockKind.warmup,
          title: 'Warm-up',
        )).dataOrNull!;
        final second = (await repository.addBlock(
          sessionTemplateId: session.id,
          kind: BlockKind.main,
          title: 'Main',
        )).dataOrNull!;
        await repository.addExercise(
          blockTemplateId: first.id,
          exerciseId: systemExerciseId('exCatCow'),
          targetSets: 1,
        );
        await repository.addExercise(
          blockTemplateId: second.id,
          exerciseId: systemExerciseId('exBackSquat'),
          targetSets: 3,
        );

        await repository.deleteBlock(first.id);

        final loaded = (await repository.loadProgram(program.id)).dataOrNull!;
        final blocks = loaded.phases.single.sessions.single.blocks;

        expect(blocks, hasLength(1));
        expect(blocks.single.id, second.id);
        expect(blocks.single.exercises, hasLength(1));
      },
    );
  });

  group('ordering', () {
    test('new siblings append to the end', () async {
      final program = await newProgram();
      final phase = (await repository.addPhase(
        programId: program.id,
        name: 'Cycle 1',
        startWeek: 1,
        endWeek: 3,
      )).dataOrNull!;

      final a = (await repository.addSession(
        phaseId: phase.id,
        code: 'A',
        title: 'Push',
      )).dataOrNull!;
      final b = (await repository.addSession(
        phaseId: phase.id,
        code: 'B',
        title: 'Pull',
      )).dataOrNull!;

      expect(a.orderIndex, 0);
      expect(b.orderIndex, 1);
    });

    test('a deleted sibling does not free its index for reuse', () async {
      final program = await newProgram();
      final phase = (await repository.addPhase(
        programId: program.id,
        name: 'Cycle 1',
        startWeek: 1,
        endWeek: 3,
      )).dataOrNull!;

      await repository.addSession(phaseId: phase.id, code: 'A', title: 'Push');
      final b = (await repository.addSession(
        phaseId: phase.id,
        code: 'B',
        title: 'Pull',
      )).dataOrNull!;
      await repository.deleteSession(b.id);

      final c = (await repository.addSession(
        phaseId: phase.id,
        code: 'C',
        title: 'Legs',
      )).dataOrNull!;

      // Counting live rows would hand C index 1 and collide with the hidden
      // B if it ever came back from a sync.
      expect(c.orderIndex, 2);
    });

    test('reordering rewrites the whole sibling list', () async {
      final program = await newProgram();
      final phase = (await repository.addPhase(
        programId: program.id,
        name: 'Cycle 1',
        startWeek: 1,
        endWeek: 3,
      )).dataOrNull!;
      final session = (await repository.addSession(
        phaseId: phase.id,
        code: 'A',
        title: 'Push',
      )).dataOrNull!;

      final warmup = (await repository.addBlock(
        sessionTemplateId: session.id,
        kind: BlockKind.warmup,
        title: 'Warm-up',
      )).dataOrNull!;
      final main = (await repository.addBlock(
        sessionTemplateId: session.id,
        kind: BlockKind.main,
        title: 'Main',
      )).dataOrNull!;
      final cooldown = (await repository.addBlock(
        sessionTemplateId: session.id,
        kind: BlockKind.cooldown,
        title: 'Cool-down',
      )).dataOrNull!;

      await repository.reorderBlocks([main.id, cooldown.id, warmup.id]);

      final loaded = (await repository.loadProgram(program.id)).dataOrNull!;
      final blocks = loaded.phases.single.sessions.single.blocks;

      expect(blocks.map((b) => b.id), [main.id, cooldown.id, warmup.id]);
      expect(blocks.map((b) => b.orderIndex), [0, 1, 2]);
    });
  });

  group('validation', () {
    test('rejects an inverted phase week range', () async {
      final program = await newProgram();

      final result = await repository.addPhase(
        programId: program.id,
        name: 'Backwards',
        startWeek: 5,
        endWeek: 2,
      );

      expect(result.failureOrNull, isA<ParseFailure>());
    });

    test('rejects a week-zero phase — program weeks are 1-based', () async {
      final program = await newProgram();

      final result = await repository.addPhase(
        programId: program.id,
        name: 'Week zero',
        startWeek: 0,
        endWeek: 2,
      );

      expect(result.failureOrNull, isA<ParseFailure>());
    });

    test('rejects a weekday outside 1–7', () async {
      final program = await newProgram();
      final phase = (await repository.addPhase(
        programId: program.id,
        name: 'Cycle 1',
        startWeek: 1,
        endWeek: 3,
      )).dataOrNull!;

      final result = await repository.addSession(
        phaseId: phase.id,
        code: 'A',
        title: 'Push',
        dayOfWeek: 0,
      );

      // A 0 here would silently never match a real day when the schedule is
      // materialized.
      expect(result.failureOrNull, isA<ParseFailure>());
    });

    test('rejects zero sets and an inverted rep range', () async {
      final program = await newProgram();
      final phase = (await repository.addPhase(
        programId: program.id,
        name: 'Cycle 1',
        startWeek: 1,
        endWeek: 3,
      )).dataOrNull!;
      final session = (await repository.addSession(
        phaseId: phase.id,
        code: 'A',
        title: 'Push',
      )).dataOrNull!;
      final block = (await repository.addBlock(
        sessionTemplateId: session.id,
        kind: BlockKind.main,
        title: 'Main',
      )).dataOrNull!;

      expect(
        (await repository.addExercise(
          blockTemplateId: block.id,
          exerciseId: systemExerciseId('exBackSquat'),
          targetSets: 0,
        )).failureOrNull,
        isA<ParseFailure>(),
      );

      // Reps or the clock, never both: two prescriptions on one slot leave the
      // logger with no single field to write.
      expect(
        (await repository.addExercise(
          blockTemplateId: block.id,
          exerciseId: systemExerciseId('exBackSquat'),
          targetSets: 3,
          targetReps: 8,
          targetDurationSec: 600,
        )).failureOrNull,
        isA<ParseFailure>(),
      );

      expect(
        (await repository.addExercise(
          blockTemplateId: block.id,
          exerciseId: systemExerciseId('exBackSquat'),
          targetSets: 3,
          targetReps: 0,
        )).failureOrNull,
        isA<ParseFailure>(),
      );
    });

    test('an exercise slot must point at a real catalog row', () async {
      final program = await newProgram();
      final phase = (await repository.addPhase(
        programId: program.id,
        name: 'Cycle 1',
        startWeek: 1,
        endWeek: 3,
      )).dataOrNull!;
      final session = (await repository.addSession(
        phaseId: phase.id,
        code: 'A',
        title: 'Push',
      )).dataOrNull!;
      final block = (await repository.addBlock(
        sessionTemplateId: session.id,
        kind: BlockKind.main,
        title: 'Main',
      )).dataOrNull!;

      final result = await repository.addExercise(
        blockTemplateId: block.id,
        exerciseId: 'not-in-the-catalog',
        targetSets: 3,
      );

      // The foreign key catches it, and the repository turns it into a
      // failure rather than an exception crossing into the UI.
      expect(result.failureOrNull, isNotNull);
    });
  });
}
