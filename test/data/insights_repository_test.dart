import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:groove/data/db/app_database.dart';
import 'package:groove/data/repositories/check_in_repository_impl.dart';
import 'package:groove/data/repositories/insights_repository_impl.dart';
import 'package:groove/data/repositories/log_repository_impl.dart';
import 'package:groove/data/repositories/plan_repository_impl.dart';
import 'package:groove/data/repositories/schedule_repository_impl.dart';
import 'package:groove/domain/enums/training_enums.dart';
import 'package:groove/domain/repositories/check_in_repository.dart';
import 'package:groove/domain/repositories/insights_repository.dart';
import 'package:groove/domain/repositories/log_repository.dart';
import 'package:groove/domain/repositories/plan_repository.dart';
import 'package:groove/domain/repositories/schedule_repository.dart';
import 'package:groove/domain/values/calendar_date.dart';
import 'package:groove/domain/values/insights_range.dart';
import 'package:groove/domain/values/schedule_pattern.dart';

void main() {
  late AppDatabase db;
  late PlanRepository plan;
  late ScheduleRepository schedule;
  late LogRepository log;
  late CheckInRepository checkIns;
  late InsightsRepository insights;

  // A Sunday, so the seeded weekly pattern lands on the start date itself.
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
    checkIns = CheckInRepositoryImpl(db.checkInDao);
    insights = InsightsRepositoryImpl(db.insightsDao);
  });

  tearDown(() => db.close());

  /// A two-week program with one gym day a week prescribing 4 sets. Returns
  /// the scheduled gym days, in date order.
  Future<List<String>> seedProgram() async {
    final program = (await plan.createProgram(
      name: 'Block',
      startDate: start,
    )).dataOrNull!;
    final phase = (await plan.addPhase(
      programId: program.id,
      name: 'Cycle 1',
      startWeek: 1,
      endWeek: 2,
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
      targetReps: 8,
    );

    await schedule.commitSchedule(
      programId: program.id,
      pattern: SchedulePattern.weekly({
        DateTime.sunday: const DayAssignment.gym('A'),
      }),
    );
    await plan.setActiveProgram(program.id);

    final days = await schedule.watchProgramSchedule(program.id).first;
    return [
      for (final day in days)
        if (day.kind == ScheduledSessionKind.gym) day.id,
    ];
  }

  group('adherence', () {
    test('counts planned sets from the template and completed from logs', () async {
      final days = await seedProgram();
      final session = (await log.startSession(
        scheduledSessionId: days.first,
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
      await log.finalizeSession(
        sessionLogId: session.id,
        scheduledSessionId: days.first,
        plannedSets: 4,
      );

      final stats = await insights
          .watchAdherence(InsightsWindow.day(start))
          .first;

      expect(stats.plannedSets, 4);
      expect(stats.completedSets, 3);
      expect(stats.plannedSessions, 1);
      expect(stats.completedSessions, 1);
      expect(stats.adherence, closeTo(0.75, 0.0001));
    });

    test('a window with no plan reports null adherence, not zero', () async {
      await seedProgram();

      // A Monday inside the program with no gym day on it.
      final stats = await insights
          .watchAdherence(InsightsWindow.day(start.addDays(1)))
          .first;

      expect(stats.plannedSets, 0);
      expect(stats.adherence, isNull);
      expect(stats.hasData, isFalse);
    });

    test('the window excludes days outside it', () async {
      final days = await seedProgram();
      final session = (await log.startSession(
        scheduledSessionId: days[1],
      )).dataOrNull!;
      await log.logSet(
        sessionLogId: session.id,
        exerciseId: squat,
        setIndex: 0,
        reps: 8,
        weightKg: 100,
      );

      // Week one only: the set above was logged in week two.
      final week = await insights
          .watchAdherence(InsightsWindow.week(start, firstWeekday: DateTime.monday))
          .first;
      expect(week.completedSets, 0);

      final all = await insights.watchAdherence(DateRange.unbounded).first;
      expect(all.completedSets, 1);
      expect(all.plannedSets, 8);
    });
  });

  group('skip breakdown', () {
    test('groups skipped sets by reason and keeps pain separable', () async {
      final days = await seedProgram();
      final session = (await log.startSession(
        scheduledSessionId: days.first,
      )).dataOrNull!;

      await log.logSet(
        sessionLogId: session.id,
        exerciseId: squat,
        setIndex: 0,
        status: SetStatus.skipped,
        skipReason: SkipReason.pain,
      );
      await log.logSet(
        sessionLogId: session.id,
        exerciseId: squat,
        setIndex: 1,
        status: SetStatus.skipped,
        skipReason: SkipReason.pain,
      );
      await log.logSet(
        sessionLogId: session.id,
        exerciseId: squat,
        setIndex: 2,
        status: SetStatus.skipped,
        skipReason: SkipReason.time,
      );

      final breakdown = await insights
          .watchSkipBreakdown(DateRange.unbounded)
          .first;

      expect(breakdown.total, 3);
      expect(breakdown.painSkips, 2);
      expect(breakdown.byReason[SkipReason.time], 1);
      expect(breakdown.ranked.first.key, SkipReason.pain);
    });

    test('is empty when nothing was skipped', () async {
      await seedProgram();
      final breakdown = await insights
          .watchSkipBreakdown(DateRange.unbounded)
          .first;
      expect(breakdown.isEmpty, isTrue);
    });
  });

  group('weight trend', () {
    test('reads oldest first with a trailing average', () async {
      await checkIns.record(date: start, weightKg: 84.0);
      await checkIns.record(date: start.addDays(1), weightKg: 83.0);
      // Outside the 7-day window of the first point.
      await checkIns.record(date: start.addDays(10), weightKg: 82.0);

      final points = await insights
          .watchWeightTrend(DateRange.unbounded)
          .first;

      expect(points.map((p) => p.kg).toList(), [84.0, 83.0, 82.0]);
      expect(points[0].averageKg, closeTo(84.0, 0.0001));
      expect(points[1].averageKg, closeTo(83.5, 0.0001));
      // The two earlier points have aged out of the window.
      expect(points[2].averageKg, closeTo(82.0, 0.0001));
    });

    test('ignores check-ins carrying no weight', () async {
      await checkIns.record(date: start, waistCm: 84);

      final points = await insights
          .watchWeightTrend(DateRange.unbounded)
          .first;
      expect(points, isEmpty);
    });

    test('respects the window', () async {
      await checkIns.record(date: start, weightKg: 84.0);
      await checkIns.record(date: start.addDays(30), weightKg: 82.0);

      final points = await insights
          .watchWeightTrend(InsightsWindow.month(start))
          .first;

      expect(points, hasLength(1));
      expect(points.single.kg, 84.0);
    });
  });
}
