import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:groove/data/db/app_database.dart';
import 'package:groove/data/repositories/exercise_repository_impl.dart';
import 'package:groove/data/repositories/plan_repository_impl.dart';
import 'package:groove/domain/enums/training_enums.dart';
import 'package:groove/domain/repositories/exercise_repository.dart';
import 'package:groove/domain/repositories/plan_repository.dart';
import 'package:groove/domain/values/calendar_date.dart';
import 'package:groove/features/plan/presentation/cubit/plan_list_cubit.dart';
import 'package:groove/features/plan/presentation/cubit/plan_list_state.dart';
import 'package:groove/features/plan/presentation/cubit/reorder.dart';
import 'package:groove/features/plan/presentation/cubit/session_editor_cubit.dart';
import 'package:groove/features/plan/presentation/cubit/session_editor_state.dart';

void main() {
  group('reorderedIds', () {
    // The one piece of arithmetic in the builder that is easy to get wrong and
    // impossible to see: an off-by-one silently shifts every drag by one slot.
    const ids = ['a', 'b', 'c', 'd'];

    test('moving down accounts for the item leaving its old slot', () {
      // ReorderableListView reports the index the item would land at *before*
      // removal, so "move a to index 2" means "put a after b".
      expect(reorderedIds(ids, 0, 2), ['b', 'a', 'c', 'd']);
      expect(reorderedIds(ids, 0, 4), ['b', 'c', 'd', 'a']);
    });

    test('moving up uses the reported index directly', () {
      expect(reorderedIds(ids, 3, 0), ['d', 'a', 'b', 'c']);
      expect(reorderedIds(ids, 2, 1), ['a', 'c', 'b', 'd']);
    });

    test('a drop onto its own position changes nothing', () {
      expect(reorderedIds(ids, 1, 1), ids);
      expect(reorderedIds(ids, 1, 2), ids);
    });

    test('an out-of-range source is ignored rather than throwing', () {
      // A drag can outlive the list it started in — the underlying query can
      // re-emit mid-gesture after a sync.
      expect(reorderedIds(ids, 9, 0), ids);
      expect(reorderedIds(ids, -1, 0), ids);
      expect(reorderedIds(const [], 0, 0), isEmpty);
    });

    test('a target past the end clamps instead of throwing', () {
      expect(reorderedIds(ids, 0, 99), ['b', 'c', 'd', 'a']);
    });
  });

  group('PlanListCubit', () {
    late AppDatabase db;
    late PlanRepository repository;
    late PlanListCubit cubit;

    setUp(() {
      db = AppDatabase.withExecutor(NativeDatabase.memory());
      repository = PlanRepositoryImpl(db.planDao);
      cubit = PlanListCubit(repository: repository);
    });

    tearDown(() async {
      await cubit.close();
      await db.close();
    });

    test('starts loading, then reports an empty catalogue as data', () async {
      expect(cubit.state, const PlanListState.loading());

      await pumpEventQueue();

      expect(cubit.state, const PlanListState.data([]));
    });

    test('a created program arrives through the live query', () async {
      await pumpEventQueue();

      final failure = await cubit.createProgram(
        name: 'Ten week block',
        startDate: const CalendarDate(2026, 8, 16),
      );
      await pumpEventQueue();

      expect(failure, isNull);
      final state = cubit.state;
      expect(state, isA<PlanListData>());
      expect((state as PlanListData).programs.single.name, 'Ten week block');
    });

    test(
      'a rejected write reports a failure and leaves the list alone',
      () async {
        await pumpEventQueue();

        final failure = await cubit.createProgram(
          name: '   ',
          startDate: const CalendarDate(2026, 8, 16),
        );
        await pumpEventQueue();

        expect(failure, isNotNull);
        expect((cubit.state as PlanListData).programs, isEmpty);
      },
    );

    test('cancels its subscription on close', () async {
      await pumpEventQueue();
      await cubit.close();

      // Writing after close must not push into a closed cubit — bloc throws on
      // an emit after close, so a leaked subscription fails loudly here.
      await repository.createProgram(
        name: 'After close',
        startDate: const CalendarDate(2026, 8, 16),
      );
      await pumpEventQueue();

      expect(cubit.isClosed, isTrue);
    });
  });

  group('SessionEditorCubit', () {
    late AppDatabase db;
    late PlanRepository plan;
    late ExerciseRepository exercises;

    setUp(() {
      db = AppDatabase.withExecutor(NativeDatabase.memory());
      plan = PlanRepositoryImpl(db.planDao);
      exercises = ExerciseRepositoryImpl(db.exerciseDao);
    });

    tearDown(() => db.close());

    Future<({String programId, String sessionId})> seedSession() async {
      final program = (await plan.createProgram(
        name: 'Block',
        startDate: const CalendarDate(2026, 8, 16),
      )).dataOrNull!;
      final phase = (await plan.addPhase(
        programId: program.id,
        name: 'Cycle 1',
        startWeek: 1,
        endWeek: 3,
      )).dataOrNull!;
      final session = (await plan.addSession(
        phaseId: phase.id,
        code: 'A',
        title: 'Push',
      )).dataOrNull!;

      return (programId: program.id, sessionId: session.id);
    }

    test('waits for both the plan and the catalog before emitting', () async {
      final ids = await seedSession();
      final cubit = SessionEditorCubit(
        planRepository: plan,
        exerciseRepository: exercises,
        programId: ids.programId,
        sessionId: ids.sessionId,
      );
      addTearDown(cubit.close);

      // Emitting on the first stream alone would render a row whose exercise
      // name is still missing.
      expect(cubit.state, const SessionEditorState.loading());

      await pumpEventQueue();

      final state = cubit.state;
      expect(state, isA<SessionEditorData>());
      expect((state as SessionEditorData).session.title, 'Push');
      expect(state.exercisesById, isNotEmpty);
    });

    test('reports the session as gone when its program is deleted', () async {
      final ids = await seedSession();
      final cubit = SessionEditorCubit(
        planRepository: plan,
        exerciseRepository: exercises,
        programId: ids.programId,
        sessionId: ids.sessionId,
      );
      addTearDown(cubit.close);
      await pumpEventQueue();

      await plan.deleteProgram(ids.programId);
      await pumpEventQueue();

      // The editor's cue to leave the screen, not an error to render.
      expect(cubit.state, const SessionEditorState.gone());
    });

    test(
      'an unknown session id resolves to gone, not to loading forever',
      () async {
        final ids = await seedSession();
        final cubit = SessionEditorCubit(
          planRepository: plan,
          exerciseRepository: exercises,
          programId: ids.programId,
          sessionId: 'no-such-session',
        );
        addTearDown(cubit.close);

        await pumpEventQueue();

        expect(cubit.state, const SessionEditorState.gone());
      },
    );

    test(
      'adding a block and an exercise flows back through the query',
      () async {
        final ids = await seedSession();
        final cubit = SessionEditorCubit(
          planRepository: plan,
          exerciseRepository: exercises,
          programId: ids.programId,
          sessionId: ids.sessionId,
        );
        addTearDown(cubit.close);
        await pumpEventQueue();

        expect(
          await cubit.addBlock(kind: BlockKind.main, title: 'Main'),
          isNull,
        );
        await pumpEventQueue();

        final block = (cubit.state as SessionEditorData).session.blocks.single;
        expect(
          await cubit.addExercise(
            blockTemplateId: block.id,
            exerciseId: systemExerciseId('exBackSquat'),
            targetSets: 4,
            targetRepsMin: 8,
            targetRepsMax: 8,
          ),
          isNull,
        );
        await pumpEventQueue();

        final session = (cubit.state as SessionEditorData).session;
        expect(session.blocks.single.exercises.single.targetSets, 4);
        expect(session.totalSets, 4);
      },
    );

    test(
      'a rejected prescription reports a failure and writes nothing',
      () async {
        final ids = await seedSession();
        final cubit = SessionEditorCubit(
          planRepository: plan,
          exerciseRepository: exercises,
          programId: ids.programId,
          sessionId: ids.sessionId,
        );
        addTearDown(cubit.close);
        await pumpEventQueue();

        await cubit.addBlock(kind: BlockKind.main, title: 'Main');
        await pumpEventQueue();
        final block = (cubit.state as SessionEditorData).session.blocks.single;

        final failure = await cubit.addExercise(
          blockTemplateId: block.id,
          exerciseId: systemExerciseId('exBackSquat'),
          targetSets: 0,
        );
        await pumpEventQueue();

        expect(failure, isNotNull);
        expect(
          (cubit.state as SessionEditorData).session.blocks.single.exercises,
          isEmpty,
        );
      },
    );
  });
}
