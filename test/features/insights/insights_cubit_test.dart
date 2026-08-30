import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:groove/data/db/app_database.dart';
import 'package:groove/data/repositories/check_in_repository_impl.dart';
import 'package:groove/data/repositories/insights_repository_impl.dart';
import 'package:groove/data/repositories/plan_repository_impl.dart';
import 'package:groove/domain/repositories/check_in_repository.dart';
import 'package:groove/domain/repositories/insights_repository.dart';
import 'package:groove/domain/repositories/plan_repository.dart';
import 'package:groove/domain/values/calendar_date.dart';
import 'package:groove/domain/values/insights_range.dart';
import 'package:groove/features/insights/presentation/cubit/insights_cubit.dart';
import 'package:groove/features/insights/presentation/cubit/insights_range_cubit.dart';

void main() {
  late AppDatabase db;
  late PlanRepository plan;
  late CheckInRepository checkIns;
  late InsightsRepository insights;

  // A Thursday, mid-program.
  const today = CalendarDate(2026, 9, 3);
  DateTime now() => DateTime(2026, 9, 3, 18);

  setUp(() {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    plan = PlanRepositoryImpl(db.planDao);
    checkIns = CheckInRepositoryImpl(db.checkInDao);
    insights = InsightsRepositoryImpl(db.insightsDao);
  });

  tearDown(() => db.close());

  /// A live program of two three-week phases starting Mon 17 Aug 2026.
  Future<void> seedProgram() async {
    final program = (await plan.createProgram(
      name: 'Block',
      startDate: const CalendarDate(2026, 8, 17),
    )).dataOrNull!;
    await plan.addPhase(
      programId: program.id,
      name: 'Cycle 1',
      startWeek: 1,
      endWeek: 3,
    );
    await plan.addPhase(
      programId: program.id,
      name: 'Cycle 2',
      startWeek: 4,
      endWeek: 6,
    );
    await plan.setActiveProgram(program.id);
  }

  group('InsightsRangeCubit', () {
    test('opens on the week containing today', () async {
      final cubit = InsightsRangeCubit(planRepository: plan, now: now);
      addTearDown(cubit.close);

      cubit.setFirstDayOfWeek(DateTime.monday);

      expect(cubit.state.kind, InsightsRangeKind.week);
      expect(cubit.state.range.start, const CalendarDate(2026, 8, 31));
      expect(cubit.state.range.end, const CalendarDate(2026, 9, 6));
    });

    test('hides Cycle until a program with phases is running', () async {
      final cubit = InsightsRangeCubit(planRepository: plan, now: now);
      addTearDown(cubit.close);

      // Drain the first (programless) emission.
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.availableKinds, isNot(contains(InsightsRangeKind.cycle)));

      await seedProgram();
      await cubit.stream.firstWhere((state) => state.offersCycle);

      expect(cubit.state.availableKinds, contains(InsightsRangeKind.cycle));
    });

    test('the cycle window is the phase today falls in', () async {
      await seedProgram();
      final cubit = InsightsRangeCubit(planRepository: plan, now: now);
      addTearDown(cubit.close);
      await cubit.stream.firstWhere((state) => state.offersCycle);

      cubit.selectKind(InsightsRangeKind.cycle);

      expect(cubit.state.phase?.name, 'Cycle 1');
      expect(cubit.state.range.start, const CalendarDate(2026, 8, 17));
      expect(cubit.state.range.end, const CalendarDate(2026, 9, 6));
    });

    test('cycle navigation walks phases and stops at the ends', () async {
      await seedProgram();
      final cubit = InsightsRangeCubit(planRepository: plan, now: now);
      addTearDown(cubit.close);
      await cubit.stream.firstWhere((state) => state.offersCycle);

      cubit.selectKind(InsightsRangeKind.cycle);
      expect(cubit.state.canGoBack, isFalse);

      cubit.next();
      expect(cubit.state.phase?.name, 'Cycle 2');
      // Nothing after the last phase, so the arrow is off rather than walking
      // into a window with no program behind it.
      expect(cubit.state.canGoForward, isFalse);

      cubit.previous();
      expect(cubit.state.phase?.name, 'Cycle 1');
    });

    test('never walks forward past today', () async {
      final cubit = InsightsRangeCubit(planRepository: plan, now: now);
      addTearDown(cubit.close);
      cubit.setFirstDayOfWeek(DateTime.monday);

      expect(cubit.state.canGoForward, isFalse);

      cubit.previous();
      expect(cubit.state.range.start, const CalendarDate(2026, 8, 24));
      expect(cubit.state.canGoForward, isTrue);

      cubit.next();
      expect(cubit.state.range.start, const CalendarDate(2026, 8, 31));
    });

    test('All is a single unbounded window with no navigation', () async {
      final cubit = InsightsRangeCubit(planRepository: plan, now: now);
      addTearDown(cubit.close);

      cubit.selectKind(InsightsRangeKind.all);

      expect(cubit.state.range, DateRange.unbounded);
      expect(cubit.state.canGoBack, isFalse);
      expect(cubit.state.canGoForward, isFalse);
    });

    test('falls back to Month if the program behind a cycle disappears', () async {
      await seedProgram();
      final cubit = InsightsRangeCubit(planRepository: plan, now: now);
      addTearDown(cubit.close);
      await cubit.stream.firstWhere((state) => state.offersCycle);

      cubit.selectKind(InsightsRangeKind.cycle);

      final programs = await plan.watchPrograms().first;
      await plan.deleteProgram(programs.single.id);
      await cubit.stream.firstWhere((state) => !state.offersCycle);

      expect(cubit.state.kind, InsightsRangeKind.month);
      expect(cubit.state.range.start, const CalendarDate(2026, 9, 1));
    });
  });

  group('InsightsCubit', () {
    test('emits once every query for the window has landed', () async {
      await checkIns.record(date: today, weightKg: 82.5);

      final cubit = InsightsCubit(repository: insights);
      addTearDown(cubit.close);

      expect(cubit.state, isA<InsightsLoading>());

      cubit.setRange(DateRange.unbounded);
      final state = await cubit.stream.firstWhere((s) => s is InsightsData)
          as InsightsData;

      expect(state.range, DateRange.unbounded);
      expect(state.weightTrend, hasLength(1));
      expect(state.adherence, isNotNull);
    });

    test('keeps the previous window on screen until the new one lands', () async {
      await checkIns.record(date: today, weightKg: 82.5);

      final cubit = InsightsCubit(repository: insights);
      addTearDown(cubit.close);

      cubit.setRange(DateRange.unbounded);
      await cubit.stream.firstWhere((s) => s is InsightsData);

      // A window with no weigh-in in it. The old data stays until the new
      // numbers arrive — no drop back to a skeleton.
      cubit.setRange(InsightsWindow.day(const CalendarDate(2026, 1, 1)));
      expect(cubit.state, isA<InsightsData>());

      final next = await cubit.stream.firstWhere(
        (s) => s is InsightsData && s.weightTrend.isEmpty,
      );
      expect((next as InsightsData).weightTrend, isEmpty);
    });

    test('setting the same range again does not resubscribe', () async {
      final cubit = InsightsCubit(repository: insights);
      addTearDown(cubit.close);

      cubit.setRange(DateRange.unbounded);
      final first = await cubit.stream.firstWhere((s) => s is InsightsData);

      cubit.setRange(DateRange.unbounded);
      expect(cubit.state, same(first));
    });
  });
}
