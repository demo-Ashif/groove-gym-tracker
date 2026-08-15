import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:groove/core/error/failure.dart';
import 'package:groove/data/db/app_database.dart';
import 'package:groove/data/repositories/log_repository_impl.dart';
import 'package:groove/data/repositories/plan_repository_impl.dart';
import 'package:groove/data/repositories/schedule_repository_impl.dart';
import 'package:groove/domain/enums/training_enums.dart';
import 'package:groove/domain/repositories/log_repository.dart';
import 'package:groove/domain/repositories/plan_repository.dart';
import 'package:groove/domain/repositories/schedule_repository.dart';
import 'package:groove/domain/values/calendar_date.dart';
import 'package:groove/domain/values/schedule_pattern.dart';

void main() {
  late AppDatabase db;
  late PlanRepository plan;
  late ScheduleRepository schedule;
  late LogRepository log;

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
  });

  tearDown(() => db.close());

  /// A one-week program with a single Day A holding one 4-set exercise, then
  /// a committed calendar. Returns the first gym day.
  Future<String> seedScheduledDay() async {
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

    final days = await schedule.watchProgramSchedule(program.id).first;
    return days.firstWhere((d) => d.kind == ScheduledSessionKind.gym).id;
  }

  group('starting and resuming', () {
    test('starting a session marks its day in progress', () async {
      final scheduledId = await seedScheduledDay();

      final session = (await log.startSession(
        scheduledSessionId: scheduledId,
      )).dataOrNull!;

      expect(session.isActive, isTrue);
      expect(session.sets, isEmpty);

      final day = (await schedule.watchRange(from: start, to: start).first)
          .firstWhere((d) => d.id == scheduledId);
      expect(day.status, ScheduledSessionStatus.inProgress);
    });

    test('an in-progress session is discoverable after a cold start', () async {
      final scheduledId = await seedScheduledDay();
      final session = (await log.startSession(
        scheduledSessionId: scheduledId,
      )).dataOrNull!;

      await log.logSet(
        sessionLogId: session.id,
        exerciseId: squat,
        setIndex: 0,
        reps: 8,
        weightKg: 100,
      );

      // Exactly what the app does on launch: no id in hand, just "is anything
      // running?" (ADR §9.4).
      final resumed = await log.watchActiveSession().first;

      expect(resumed, isNotNull);
      expect(resumed!.id, session.id);
      expect(resumed.sets, hasLength(1));
    });

    test('a finished session is no longer active', () async {
      final scheduledId = await seedScheduledDay();
      final session = (await log.startSession(
        scheduledSessionId: scheduledId,
      )).dataOrNull!;

      await log.logSet(
        sessionLogId: session.id,
        exerciseId: squat,
        setIndex: 0,
        reps: 8,
        weightKg: 100,
      );
      await log.finalizeSession(
        sessionLogId: session.id,
        scheduledSessionId: scheduledId,
        plannedSets: 4,
      );

      expect(await log.watchActiveSession().first, isNull);
    });

    test('discarding returns the day to upcoming and hides the sets', () async {
      final scheduledId = await seedScheduledDay();
      final session = (await log.startSession(
        scheduledSessionId: scheduledId,
      )).dataOrNull!;
      await log.logSet(
        sessionLogId: session.id,
        exerciseId: squat,
        setIndex: 0,
        reps: 8,
        weightKg: 100,
      );

      await log.discardSession(
        sessionLogId: session.id,
        scheduledSessionId: scheduledId,
      );

      expect(await log.watchActiveSession().first, isNull);
      final day = (await schedule.watchRange(from: start, to: start).first)
          .firstWhere((d) => d.id == scheduledId);
      // A phantom in-progress workout would block Today forever.
      expect(day.status, ScheduledSessionStatus.upcoming);
    });
  });

  group('logging sets', () {
    test('every set is on disk the moment it is logged', () async {
      final scheduledId = await seedScheduledDay();
      final session = (await log.startSession(
        scheduledSessionId: scheduledId,
      )).dataOrNull!;

      for (var index = 0; index < 3; index++) {
        await log.logSet(
          sessionLogId: session.id,
          exerciseId: squat,
          setIndex: index,
          reps: 8,
          weightKg: 100,
        );
      }

      // Read back through a fresh query, as a cold start would.
      final reloaded = await log.watchSession(session.id).first;
      expect(reloaded!.sets, hasLength(3));
      expect(reloaded.completedSets, 3);
    });

    test(
      'confirming the same chip twice corrects the set, not adds one',
      () async {
        final scheduledId = await seedScheduledDay();
        final session = (await log.startSession(
          scheduledSessionId: scheduledId,
        )).dataOrNull!;

        await log.logSet(
          sessionLogId: session.id,
          exerciseId: squat,
          setIndex: 0,
          reps: 8,
          weightKg: 100,
        );
        await log.logSet(
          sessionLogId: session.id,
          exerciseId: squat,
          setIndex: 0,
          reps: 8,
          weightKg: 102.5,
        );

        final sets = (await log.watchSession(session.id).first)!.sets;
        expect(sets, hasLength(1));
        expect(sets.single.weightKg, 102.5);
      },
    );

    test(
      'a skipped set must carry a reason, and only a skipped set may',
      () async {
        final scheduledId = await seedScheduledDay();
        final session = (await log.startSession(
          scheduledSessionId: scheduledId,
        )).dataOrNull!;

        expect(
          (await log.logSet(
            sessionLogId: session.id,
            exerciseId: squat,
            setIndex: 0,
            status: SetStatus.skipped,
          )).failureOrNull,
          isA<ParseFailure>(),
        );

        expect(
          (await log.logSet(
            sessionLogId: session.id,
            exerciseId: squat,
            setIndex: 0,
            skipReason: SkipReason.pain,
          )).failureOrNull,
          isA<ParseFailure>(),
        );

        expect(
          (await log.logSet(
            sessionLogId: session.id,
            exerciseId: squat,
            setIndex: 0,
            status: SetStatus.skipped,
            skipReason: SkipReason.pain,
          )).isSuccess,
          isTrue,
        );
      },
    );

    test(
      'the last completed set comes from an earlier session, not this one',
      () async {
        final scheduledId = await seedScheduledDay();

        final first = (await log.startSession(
          scheduledSessionId: scheduledId,
        )).dataOrNull!;
        await log.logSet(
          sessionLogId: first.id,
          exerciseId: squat,
          setIndex: 0,
          reps: 8,
          weightKg: 100,
        );
        await log.finalizeSession(
          sessionLogId: first.id,
          scheduledSessionId: scheduledId,
          plannedSets: 4,
        );

        final second = (await log.startSession(
          scheduledSessionId: scheduledId,
        )).dataOrNull!;
        await log.logSet(
          sessionLogId: second.id,
          exerciseId: squat,
          setIndex: 0,
          reps: 8,
          weightKg: 999,
        );

        final previous = (await log.lastCompletedSet(
          exerciseId: squat,
          excludingSessionLogId: second.id,
        )).dataOrNull;

        // Pre-filling from the set you just logged would make the suggestion
        // chase itself up the rack.
        expect(previous!.weightKg, 100);
      },
    );
  });

  group('finalizing', () {
    test('a full session completes its day', () async {
      final scheduledId = await seedScheduledDay();
      final session = (await log.startSession(
        scheduledSessionId: scheduledId,
      )).dataOrNull!;

      for (var index = 0; index < 4; index++) {
        await log.logSet(
          sessionLogId: session.id,
          exerciseId: squat,
          setIndex: index,
          reps: 8,
          weightKg: 100,
        );
      }

      await log.finalizeSession(
        sessionLogId: session.id,
        scheduledSessionId: scheduledId,
        plannedSets: 4,
        sessionRpe: 7.5,
        energy: 4,
      );

      final day = (await schedule.watchRange(from: start, to: start).first)
          .firstWhere((d) => d.id == scheduledId);
      expect(day.status, ScheduledSessionStatus.completed);

      final finished = (await log.watchSession(session.id).first)!;
      expect(finished.isActive, isFalse);
      expect(finished.sessionRpe, 7.5);
      expect(finished.energy, 4);
    });

    test('a session cut short settles as partial', () async {
      final scheduledId = await seedScheduledDay();
      final session = (await log.startSession(
        scheduledSessionId: scheduledId,
      )).dataOrNull!;

      await log.logSet(
        sessionLogId: session.id,
        exerciseId: squat,
        setIndex: 0,
        reps: 8,
        weightKg: 100,
      );

      await log.finalizeSession(
        sessionLogId: session.id,
        scheduledSessionId: scheduledId,
        plannedSets: 4,
      );

      final day = (await schedule.watchRange(from: start, to: start).first)
          .firstWhere((d) => d.id == scheduledId);
      // One set of four is not a workout you did.
      expect(day.status, ScheduledSessionStatus.partial);
    });

    test('logging nothing settles as skipped', () async {
      final scheduledId = await seedScheduledDay();
      final session = (await log.startSession(
        scheduledSessionId: scheduledId,
      )).dataOrNull!;

      await log.finalizeSession(
        sessionLogId: session.id,
        scheduledSessionId: scheduledId,
        plannedSets: 4,
      );

      final day = (await schedule.watchRange(from: start, to: start).first)
          .firstWhere((d) => d.id == scheduledId);
      // Starting a session and walking out is not a partial workout.
      expect(day.status, ScheduledSessionStatus.skipped);
    });
  });

  group('settleStatus', () {
    test('draws the line at two thirds of the prescribed work', () {
      expect(
        settleStatus(completedSets: 8, plannedSets: 12),
        ScheduledSessionStatus.completed,
      );
      expect(
        settleStatus(completedSets: 7, plannedSets: 12),
        ScheduledSessionStatus.partial,
      );
    });

    test('an unplanned session with work in it counts as completed', () {
      expect(
        settleStatus(completedSets: 5, plannedSets: 0),
        ScheduledSessionStatus.completed,
      );
    });

    test('nothing logged is skipped, however much was planned', () {
      expect(
        settleStatus(completedSets: 0, plannedSets: 12),
        ScheduledSessionStatus.skipped,
      );
      expect(
        settleStatus(completedSets: 0, plannedSets: 0),
        ScheduledSessionStatus.skipped,
      );
    });
  });
}
