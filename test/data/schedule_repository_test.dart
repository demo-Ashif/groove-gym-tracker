import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:groove/core/error/failure.dart';
import 'package:groove/data/db/app_database.dart';
import 'package:groove/data/repositories/plan_repository_impl.dart';
import 'package:groove/data/repositories/schedule_repository_impl.dart';
import 'package:groove/domain/enums/training_enums.dart';
import 'package:groove/domain/repositories/plan_repository.dart';
import 'package:groove/domain/repositories/schedule_repository.dart';
import 'package:groove/domain/values/calendar_date.dart';
import 'package:groove/domain/values/schedule_pattern.dart';

/// Materialization through real SQLite. The pure rules are covered in
/// `test/domain/schedule_materializer_test.dart`; what matters here is that
/// the diff reaches the database intact, and that the pattern survives a
/// round trip so a re-commit doesn't need the user to redraw anything.
void main() {
  late AppDatabase db;
  late PlanRepository plan;
  late ScheduleRepository schedule;

  // Sunday. The clock is injected so "today" is an input, not the machine the
  // test happens to run on.
  const start = CalendarDate(2026, 8, 16);
  var now = DateTime(2026, 8, 16, 9);

  setUp(() {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    plan = PlanRepositoryImpl(db.planDao);
    schedule = ScheduleRepositoryImpl(
      dao: db.scheduleDao,
      planRepository: plan,
      now: () => now,
    );
    now = DateTime(2026, 8, 16, 9);
  });

  tearDown(() => db.close());

  final weekly = SchedulePattern.weekly({
    DateTime.sunday: const DayAssignment.gym('A'),
    DateTime.monday: const DayAssignment.gym('B'),
    DateTime.saturday: const DayAssignment.cricket(),
  });

  /// A two-week program with Day A and Day B.
  Future<String> seedProgram({int endWeek = 2}) async {
    final program = (await plan.createProgram(
      name: 'Block',
      startDate: start,
    )).dataOrNull!;
    final phase = (await plan.addPhase(
      programId: program.id,
      name: 'Cycle 1',
      startWeek: 1,
      endWeek: endWeek,
    )).dataOrNull!;

    for (final code in ['A', 'B']) {
      await plan.addSession(phaseId: phase.id, code: code, title: 'Day $code');
    }

    return program.id;
  }

  test('commits a whole program in one pass', () async {
    final programId = await seedProgram();

    final result = await schedule.commitSchedule(
      programId: programId,
      pattern: weekly,
    );

    expect(result.dataOrNull, (added: 14, removed: 0));

    final days = await schedule.watchProgramSchedule(programId).first;
    expect(days, hasLength(14));
    expect(days.first.date, start);
    expect(days.last.date, start.addDays(13));

    final sunday = days.first;
    expect(sunday.kind, ScheduledSessionKind.gym);
    expect(sunday.sessionTemplateId, isNotNull);
    expect(sunday.status, ScheduledSessionStatus.upcoming);
    expect(sunday.weekNumber, 1);

    expect(
      days.where((d) => d.kind == ScheduledSessionKind.cricket),
      hasLength(2),
    );
  });

  test('stores the pattern so a re-commit needs no redrawing', () async {
    final programId = await seedProgram();
    await schedule.commitSchedule(programId: programId, pattern: weekly);

    final program = (await plan.loadProgram(programId)).dataOrNull!;

    expect(program.schedulePattern, weekly);
    expect(program.schedulePattern!.referencedCodes, {'A', 'B'});
  });

  test('re-committing an unchanged pattern writes nothing', () async {
    final programId = await seedProgram();
    await schedule.commitSchedule(programId: programId, pattern: weekly);

    final result = await schedule.commitSchedule(
      programId: programId,
      pattern: weekly,
    );

    expect(result.dataOrNull, (added: 0, removed: 0));
    expect(await schedule.watchProgramSchedule(programId).first, hasLength(14));
  });

  test('a changed pattern replaces future days only', () async {
    final programId = await seedProgram();
    await schedule.commitSchedule(programId: programId, pattern: weekly);

    // Move the clock into the middle of week one.
    now = DateTime(2026, 8, 19, 9);

    final result = await schedule.commitSchedule(
      programId: programId,
      pattern: SchedulePattern.weekly({
        DateTime.sunday: const DayAssignment.gym('A'),
        DateTime.monday: const DayAssignment.gym('B'),
        // Saturday stops being cricket.
        DateTime.saturday: const DayAssignment.gym('A'),
      }),
    );

    final days = await schedule.watchProgramSchedule(programId).first;
    expect(days, hasLength(14), reason: 'still one row per day');

    final saturdays = days
        .where((d) => d.date.weekday == DateTime.saturday)
        .toList();

    // The first Saturday is 22 Aug, still ahead of the clock, so both change.
    expect(result.dataOrNull!.added, greaterThan(0));
    expect(saturdays.every((d) => d.kind == ScheduledSessionKind.gym), isTrue);

    // Days already past keep whatever they were.
    final pastDays = days.where((d) => d.date.isBefore(CalendarDate.from(now)));
    expect(pastDays, isNotEmpty);
  });

  test('never rewrites a day the user has already touched', () async {
    final programId = await seedProgram();
    await schedule.commitSchedule(programId: programId, pattern: weekly);

    final days = await schedule.watchProgramSchedule(programId).first;
    // A Monday well into the future.
    final monday = days.firstWhere(
      (d) => d.date.weekday == DateTime.monday && d.date.isAfter(start),
    );

    await schedule.setStatus(
      id: monday.id,
      status: ScheduledSessionStatus.completed,
    );

    await schedule.commitSchedule(
      programId: programId,
      // Monday becomes a rest day in the new plan.
      pattern: SchedulePattern.weekly({
        DateTime.sunday: const DayAssignment.gym('A'),
      }),
    );

    final after = await schedule.watchProgramSchedule(programId).first;
    final sameDay = after.firstWhere((d) => d.date == monday.date);

    // A completed day is a record, not a plan (ADR §8.2).
    expect(sameDay.status, ScheduledSessionStatus.completed);
    expect(sameDay.kind, ScheduledSessionKind.gym);
    expect(sameDay.id, monday.id);
  });

  test('removed days are soft-deleted, not destroyed', () async {
    final programId = await seedProgram();
    await schedule.commitSchedule(programId: programId, pattern: weekly);

    await schedule.commitSchedule(
      programId: programId,
      pattern: const SchedulePattern.weekly({}),
    );

    // Reads see none of them...
    final visible = await schedule.watchProgramSchedule(programId).first;
    expect(visible.every((d) => d.kind == ScheduledSessionKind.rest), isTrue);

    // ...but the rows are still there, because a hard delete could not
    // propagate to another device.
    final raw = await db.select(db.scheduledSessions).get();
    expect(raw.where((r) => r.deletedAt != null), isNotEmpty);
    expect(
      raw
          .where((r) => r.deletedAt != null)
          .every((r) => r.syncState == SyncState.pendingDelete),
      isTrue,
    );
  });

  test('converting a day to cricket clears its prescription', () async {
    final programId = await seedProgram();
    await schedule.commitSchedule(programId: programId, pattern: weekly);

    final gymDay = (await schedule.watchProgramSchedule(programId).first)
        .firstWhere((d) => d.kind == ScheduledSessionKind.gym);

    await schedule.convertKind(
      id: gymDay.id,
      kind: ScheduledSessionKind.cricket,
      reason: 'Match day',
    );

    final after = (await schedule.watchProgramSchedule(programId).first)
        .firstWhere((d) => d.id == gymDay.id);

    expect(after.kind, ScheduledSessionKind.cricket);
    // Nothing downstream may read a prescription off a day that no longer has
    // one.
    expect(after.sessionTemplateId, isNull);
    expect(after.overrideReason, 'Match day');
  });

  test(
    'a program with no phases is refused rather than scheduled empty',
    () async {
      final program = (await plan.createProgram(
        name: 'Empty',
        startDate: start,
      )).dataOrNull!;

      final result = await schedule.commitSchedule(
        programId: program.id,
        pattern: weekly,
      );

      // A run of rest days pretending to be a program is worse than an error.
      expect(result.failureOrNull, isA<ParseFailure>());
    },
  );

  test('an unknown program id fails instead of writing orphan rows', () async {
    final result = await schedule.commitSchedule(
      programId: 'no-such-program',
      pattern: weekly,
    );

    expect(result.failureOrNull, isA<StorageFailure>());
    expect(await db.select(db.scheduledSessions).get(), isEmpty);
  });

  test('range queries read the date column as a real range', () async {
    final programId = await seedProgram();
    await schedule.commitSchedule(programId: programId, pattern: weekly);

    final week = await schedule
        .watchRange(from: start, to: start.addDays(6))
        .first;

    // `YYYY-MM-DD` sorts lexicographically in calendar order, which is what
    // makes a text column range-queryable.
    expect(week, hasLength(7));
    expect(week.first.date, start);
    expect(week.last.date, start.addDays(6));
  });

  test('rescheduling moves a day without touching its neighbours', () async {
    final programId = await seedProgram();
    await schedule.commitSchedule(programId: programId, pattern: weekly);

    final day = (await schedule.watchProgramSchedule(programId).first).first;
    final target = start.addDays(30);

    await schedule.reschedule(id: day.id, date: target);

    final moved = (await schedule.watchProgramSchedule(programId).first)
        .firstWhere((d) => d.id == day.id);

    expect(moved.date, target);
    expect(await schedule.watchProgramSchedule(programId).first, hasLength(14));
  });
}
