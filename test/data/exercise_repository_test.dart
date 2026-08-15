import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:groove/core/error/failure.dart';
import 'package:groove/data/db/app_database.dart';
import 'package:groove/data/repositories/exercise_repository_impl.dart';
import 'package:groove/domain/entities/exercise.dart';
import 'package:groove/domain/enums/training_enums.dart';
import 'package:groove/domain/repositories/exercise_repository.dart';

/// The row → entity boundary. Everything above this line works with pure
/// entities and has never heard of SQLite.
void main() {
  late AppDatabase db;
  late ExerciseRepository repository;

  setUp(() {
    db = AppDatabase.withExecutor(NativeDatabase.memory());
    repository = ExerciseRepositoryImpl(db.exerciseDao);
  });

  tearDown(() => db.close());

  test('maps a seeded row onto a system entity', () async {
    final result = await repository.findById(
      systemExerciseId('exRomanianDeadlift'),
    );

    final exercise = result.dataOrNull;
    expect(exercise, isA<Exercise>());
    expect(exercise!.nameKey, 'exRomanianDeadlift');
    expect(exercise.customName, isNull);
    expect(exercise.aliases, contains('RDL'));
    expect(exercise.primaryMuscles, contains('hamstrings'));
    expect(exercise.isSystem, isTrue);
    expect(exercise.isEditable, isFalse);
    expect(exercise.supportsE1rm, isTrue);
    expect(exercise.isHidden, isFalse);
  });

  test('an unknown id is a successful empty answer, not a failure', () async {
    // "Not found" is a legitimate result — an id can arrive from a device
    // that has synced further than this one.
    final result = await repository.findById('no-such-id');

    expect(result.isSuccess, isTrue);
    expect(result.dataOrNull, isNull);
  });

  test('a blank name is rejected before it reaches storage', () async {
    final result = await repository.createCustom(
      name: '   ',
      pattern: MovementPattern.squat,
      loadType: LoadType.barbell,
    );

    expect(result.failureOrNull, isA<ParseFailure>());
  });

  test('a created exercise comes back as an entity', () async {
    final result = await repository.createCustom(
      name: 'Zercher squat',
      pattern: MovementPattern.squat,
      loadType: LoadType.barbell,
      primaryMuscles: const ['quads'],
    );

    final exercise = result.dataOrNull;
    expect(exercise!.customName, 'Zercher squat');
    expect(exercise.nameKey, isNull);
    expect(exercise.isEditable, isTrue);
    expect(exercise.primaryMuscles, ['quads']);
  });

  test('malformed JSON degrades to an empty list instead of taking out the '
      'catalog', () async {
    final id = systemExerciseId('exBackSquat');
    // Simulates a row written by a newer client, or a bad hand-edit during
    // debugging. The screen must still render.
    await db.customStatement(
      "UPDATE exercises SET aliases = 'not json' WHERE id = ?",
      [id],
    );

    final exercise = (await repository.findById(id)).dataOrNull;

    expect(exercise, isNotNull);
    expect(exercise!.aliases, isEmpty);
  });

  test('hiding removes an exercise from the watched catalog', () async {
    final catalog = repository.watchCatalog();
    final id = systemExerciseId('exBackSquat');

    expect((await catalog.first).map((e) => e.id), contains(id));

    final result = await repository.hide(id);
    expect(result.isSuccess, isTrue);

    expect((await catalog.first).map((e) => e.id), isNot(contains(id)));
    // Still resolvable — every set log that points at it needs a name.
    expect((await repository.findById(id)).dataOrNull, isNotNull);
  });

  test('watchByPattern filters to one movement pattern', () async {
    final hinges = await repository.watchByPattern(MovementPattern.hinge).first;

    expect(hinges, isNotEmpty);
    expect(hinges.every((e) => e.pattern == MovementPattern.hinge), isTrue);
  });

  test('a confirmed alias is remembered for the next import', () async {
    final id = systemExerciseId('exLatPulldown');

    await repository.addAlias(exerciseId: id, alias: 'lat pull down');

    final matches = (await repository.findByText('lat pull down')).dataOrNull;
    expect(matches!.map((e) => e.id), contains(id));
  });
}
