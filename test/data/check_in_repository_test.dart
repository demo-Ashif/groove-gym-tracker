import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:groove/core/error/failure.dart';
import 'package:groove/data/db/app_database.dart';
import 'package:groove/data/repositories/check_in_repository_impl.dart';
import 'package:groove/domain/repositories/check_in_repository.dart';
import 'package:groove/domain/values/calendar_date.dart';

void main() {
  late AppDatabase db;
  late CheckInRepository repository;

  const monday = CalendarDate(2026, 8, 17);
  const tuesday = CalendarDate(2026, 8, 18);

  setUp(() {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    repository = CheckInRepositoryImpl(db.checkInDao);
  });

  tearDown(() => db.close());

  test('records a weigh-in and reads it back as the latest', () async {
    await repository.record(date: monday, weightKg: 82.4);

    final latest = await repository.watchLatestWeight().first;
    expect(latest!.weightKg, 82.4);
    expect(latest.date, monday);
  });

  test(
    'weighing again on the same day corrects rather than duplicates',
    () async {
      await repository.record(date: monday, weightKg: 82.4);
      await repository.record(date: monday, weightKg: 81.9);

      final all = await repository.watchCheckIns().first;
      // Stepping on the scale twice in one morning is a correction, not two
      // points on the trend.
      expect(all, hasLength(1));
      expect(all.single.weightKg, 81.9);
    },
  );

  test('a different day is a new point on the trend', () async {
    await repository.record(date: monday, weightKg: 82.4);
    await repository.record(date: tuesday, weightKg: 82.0);

    final all = await repository.watchCheckIns().first;
    expect(all, hasLength(2));
    // Newest first.
    expect(all.first.date, tuesday);
  });

  test('the latest-weight stream skips entries carrying no weight', () async {
    await repository.record(date: monday, weightKg: 82.4);
    await repository.record(date: tuesday, waistCm: 84);

    // A waist-only check-in must not blank out the weight the app reads.
    final latest = await repository.watchLatestWeight().first;
    expect(latest!.weightKg, 82.4);
    expect(latest.date, monday);
  });

  test('refuses a weight that is not a plausible bodyweight', () async {
    // The classic failure: pounds typed into a kilograms field.
    for (final weight in [0.0, -5.0, 900.0]) {
      final result = await repository.record(date: monday, weightKg: weight);
      expect(result.failureOrNull, isA<ParseFailure>(), reason: '$weight');
    }
  });

  test('deleting hides it from reads but keeps the row', () async {
    final created = (await repository.record(
      date: monday,
      weightKg: 82.4,
    )).dataOrNull!;

    await repository.delete(created.id);

    expect(await repository.watchCheckIns().first, isEmpty);
    // Soft delete: a hard one could not propagate to another device.
    final raw = await db.select(db.checkIns).get();
    expect(raw.single.deletedAt, isNotNull);
  });

  test('the trend re-emits when a weight is recorded', () async {
    final seen = <int>[];
    final subscription = repository.watchCheckIns().listen(
      (entries) => seen.add(entries.length),
    );
    addTearDown(subscription.cancel);
    await pumpEventQueue();

    await repository.record(date: monday, weightKg: 82.4);
    await pumpEventQueue();

    expect(seen.first, 0);
    expect(seen.last, 1);
  });
}
