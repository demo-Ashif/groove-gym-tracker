import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:groove/data/db/app_database.dart';
import 'package:groove/data/repositories/exercise_repository_impl.dart';
import 'package:groove/data/repositories/log_repository_impl.dart';
import 'package:groove/data/repositories/plan_repository_impl.dart';
import 'package:groove/data/repositories/schedule_repository_impl.dart';
import 'package:groove/domain/entities/plan.dart';
import 'package:groove/domain/enums/training_enums.dart';
import 'package:groove/domain/repositories/exercise_repository.dart';
import 'package:groove/domain/repositories/log_repository.dart';
import 'package:groove/domain/repositories/plan_repository.dart';
import 'package:groove/domain/repositories/schedule_repository.dart';
import 'package:groove/domain/values/calendar_date.dart';
import 'package:groove/domain/values/schedule_pattern.dart';
import 'package:groove/features/active_session/presentation/cubit/active_session_cubit.dart';
import 'package:groove/features/active_session/presentation/cubit/active_session_state.dart';

/// The logging loop end to end: cubit → repository → real SQLite.
///
/// Covers what the set chips actually do when tapped, which nothing tested
/// before — the repository tests reached `logSet` directly and never went
/// through the cubit that the screen talks to.
void main() {
  late AppDatabase db;
  late PlanRepository plan;
  late ScheduleRepository schedule;
  late LogRepository log;
  late ExerciseRepository exercises;

  const start = CalendarDate(2026, 8, 16);
  final squat = systemExerciseId('exBackSquat');

  setUp(() {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    plan = PlanRepositoryImpl(db.planDao);
    schedule = ScheduleRepositoryImpl(
      dao: db.scheduleDao,
      planRepository: plan,
      now: () => DateTime(2026, 8, 16, 9),
    );
    log = LogRepositoryImpl(db.logDao);
    exercises = ExerciseRepositoryImpl(db.exerciseDao);
  });

  tearDown(() => db.close());

  /// A committed day with one 3-set squat slot. Returns its scheduled id.
  Future<String> seedDay({int? targetReps = 8, int? targetDurationSec}) async {
    final program = (await plan.createProgram(
      name: 'Block',
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
      targetSets: 3,
      targetReps: targetReps,
      targetDurationSec: targetDurationSec,
    );

    await schedule.commitSchedule(
      programId: program.id,
      pattern: SchedulePattern.weekly({
        DateTime.sunday: const DayAssignment.gym('A'),
      }),
    );
    await plan.setActiveProgram(program.id);

    final days = await schedule.watchProgramSchedule(program.id).first;
    return days.firstWhere((d) => d.kind == ScheduledSessionKind.gym).id;
  }

  Future<ActiveSessionCubit> openSession(String scheduledId) async {
    final cubit = ActiveSessionCubit(
      logRepository: log,
      planRepository: plan,
      scheduleRepository: schedule,
      exerciseRepository: exercises,
      scheduledSessionId: scheduledId,
    );
    addTearDown(cubit.close);

    // The cubit loads the template, the catalog and the log before it can
    // emit anything useful.
    await pumpEventQueue();
    return cubit;
  }

  ExerciseTemplate slotOf(ActiveSessionCubit cubit) {
    final state = cubit.state as ActiveSessionData;
    return state.template!.blocks.single.exercises.single;
  }

  test('the screen opens with the prescription loaded', () async {
    final cubit = await openSession(await seedDay());

    final state = cubit.state;
    expect(state, isA<ActiveSessionData>());
    expect(slotOf(cubit).targetSets, 3);
  });

  test('tapping an unlogged chip logs that set', () async {
    final cubit = await openSession(await seedDay());

    final failure = await cubit.logSet(slot: slotOf(cubit), setIndex: 0);
    await pumpEventQueue();

    expect(failure, isNull, reason: 'a plain tap must not fail');

    final state = cubit.state as ActiveSessionData;
    expect(state.log.sets, hasLength(1));
    expect(state.log.sets.single.setIndex, 0);
    // Pre-filled from the prescription, which is what makes one tap one set.
    expect(state.log.sets.single.reps, 8);
  });

  test('sets can be logged out of order — chip 3 before chip 2', () async {
    final cubit = await openSession(await seedDay());
    final slot = slotOf(cubit);

    expect(await cubit.logSet(slot: slot, setIndex: 2), isNull);
    await pumpEventQueue();

    final state = cubit.state as ActiveSessionData;
    expect(state.log.sets.map((s) => s.setIndex), [2]);
  });

  test('every set of the exercise can be logged in turn', () async {
    final cubit = await openSession(await seedDay());
    final slot = slotOf(cubit);

    for (var index = 0; index < 3; index++) {
      expect(
        await cubit.logSet(slot: slot, setIndex: index),
        isNull,
        reason: 'set $index',
      );
      await pumpEventQueue();
    }

    final state = cubit.state as ActiveSessionData;
    expect(state.log.sets.map((s) => s.setIndex).toList()..sort(), [0, 1, 2]);
    expect(state.log.completedSets, 3);
  });

  group('time-based slots', () {
    test('one tap logs the prescribed duration, and no load or reps', () async {
      final cubit = await openSession(
        await seedDay(targetReps: null, targetDurationSec: 600),
      );

      final failure = await cubit.logSet(slot: slotOf(cubit), setIndex: 0);
      await pumpEventQueue();

      expect(failure, isNull);
      final set = (cubit.state as ActiveSessionData).log.sets.single;
      expect(set.durationSec, 600, reason: 'the prescription is 10 minutes');
      // A bike carries no weight and no reps; inventing them would put
      // fiction into tonnage and e1RM.
      expect(set.reps, isNull);
      expect(set.weightKg, isNull);
    });

    test('an edited duration overrides the prescription', () async {
      final cubit = await openSession(
        await seedDay(targetReps: null, targetDurationSec: 600),
      );

      // 25 minutes on the bike instead of the prescribed 10.
      await cubit.logSet(
        slot: slotOf(cubit),
        setIndex: 0,
        durationSec: 25 * 60,
      );
      await pumpEventQueue();

      expect(
        (cubit.state as ActiveSessionData).log.sets.single.durationSec,
        1500,
      );
    });

    test('load and reps are refused even if passed in', () async {
      final cubit = await openSession(
        await seedDay(targetReps: null, targetDurationSec: 600),
      );

      // The editor never offers these for a time slot, but the cubit is the
      // layer that has to guarantee it.
      await cubit.logSet(
        slot: slotOf(cubit),
        setIndex: 0,
        weightKg: 100,
        reps: 8,
      );
      await pumpEventQueue();

      final set = (cubit.state as ActiveSessionData).log.sets.single;
      expect(set.weightKg, isNull);
      expect(set.reps, isNull);
      expect(set.durationSec, 600);
    });

    test('a rep-based slot still records load and reps', () async {
      final cubit = await openSession(await seedDay());

      await cubit.logSet(slot: slotOf(cubit), setIndex: 0, weightKg: 100);
      await pumpEventQueue();

      final set = (cubit.state as ActiveSessionData).log.sets.single;
      expect(set.weightKg, 100);
      expect(set.reps, 8);
      expect(set.durationSec, isNull);
    });
  });

  test(
    'tapping the same chip again corrects it rather than adding one',
    () async {
      final cubit = await openSession(await seedDay());
      final slot = slotOf(cubit);

      await cubit.logSet(slot: slot, setIndex: 0, weightKg: 100, reps: 8);
      await pumpEventQueue();
      await cubit.logSet(slot: slot, setIndex: 0, weightKg: 105, reps: 6);
      await pumpEventQueue();

      final state = cubit.state as ActiveSessionData;
      expect(state.log.sets, hasLength(1));
      expect(state.log.sets.single.weightKg, 105);
      expect(state.log.sets.single.reps, 6);
    },
  );

  group('backfilled sessions', () {
    test('opens on a day with no program or template', () async {
      const past = CalendarDate(2026, 8, 10);
      final day = (await schedule.createBackfillDay(date: past)).dataOrNull!;

      final cubit = await openSession(day.id);

      final state = cubit.state;
      expect(state, isA<ActiveSessionData>());
      // Nothing was prescribed, so there is no template to render blocks from.
      expect((state as ActiveSessionData).template, isNull);
    });

    test(
      'is stamped with the day it happened, not the day it was typed',
      () async {
        const past = CalendarDate(2026, 8, 10);
        final day = (await schedule.createBackfillDay(date: past)).dataOrNull!;

        final cubit = await openSession(day.id);
        final log = (cubit.state as ActiveSessionData).log;

        // History sorts and charts on this; stamping it "now" would file a July
        // workout under today.
        expect(log.startedAt.year, past.year);
        expect(log.startedAt.month, past.month);
        expect(log.startedAt.day, past.day);
      },
    );

    test('reaches history once finalized', () async {
      const past = CalendarDate(2026, 8, 10);
      final day = (await schedule.createBackfillDay(date: past)).dataOrNull!;
      final cubit = await openSession(day.id);
      final logId = (cubit.state as ActiveSessionData).log.id;

      await log.finalizeSession(
        sessionLogId: logId,
        scheduledSessionId: day.id,
        plannedSets: 0,
      );
      await pumpEventQueue();

      final history = await log.watchFinishedSessions().first;
      expect(history.map((entry) => entry.log.id), contains(logId));
      // No template behind it, so the list falls back to the date.
      expect(history.single.title, isNull);
    });
  });

  test('a logged set can be cleared', () async {
    final cubit = await openSession(await seedDay());
    final slot = slotOf(cubit);

    await cubit.logSet(slot: slot, setIndex: 0);
    await pumpEventQueue();
    final setId = (cubit.state as ActiveSessionData).log.sets.single.id;

    expect(await cubit.clearSet(setId), isNull);
    await pumpEventQueue();

    expect((cubit.state as ActiveSessionData).log.sets, isEmpty);
  });
}
