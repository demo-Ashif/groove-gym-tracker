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
      bodySection: BodySection.legs,
      loadType: LoadType.barbell,
    );

    expect(result.failureOrNull, isA<ParseFailure>());
  });

  group('names are unique among a user\'s own exercises', () {
    Future<void> create(String name) async {
      final result = await repository.createCustom(
        name: name,
        pattern: MovementPattern.squat,
        bodySection: BodySection.legs,
        loadType: LoadType.barbell,
      );
      expect(result.failureOrNull, isNull, reason: 'seeding $name');
    }

    test('a duplicate name is refused, ignoring case and padding', () async {
      await create('Zercher squat');

      for (final attempt in [
        'Zercher squat',
        'zercher SQUAT',
        '  Zercher squat  ',
      ]) {
        final result = await repository.createCustom(
          name: attempt,
          pattern: MovementPattern.squat,
          bodySection: BodySection.legs,
          loadType: LoadType.barbell,
        );
        // Two rows with one name split a lift's history into two charts that
        // each look like a plateau.
        expect(result.failureOrNull, isA<ParseFailure>(), reason: attempt);
      }
    });

    test('renaming keeps the id, so history follows the exercise', () async {
      final created = (await repository.createCustom(
        name: 'Zercher squat',
        pattern: MovementPattern.squat,
        bodySection: BodySection.legs,
        loadType: LoadType.barbell,
      )).dataOrNull!;

      final result = await repository.renameCustom(
        id: created.id,
        name: 'Zercher front squat',
        bodySection: BodySection.glutes,
      );

      expect(result.failureOrNull, isNull);

      final after = (await repository.findById(created.id)).dataOrNull!;
      expect(after.id, created.id, reason: 'set logs point at the id');
      expect(after.customName, 'Zercher front squat');
      expect(after.bodySection, BodySection.glutes);
    });

    test('a rename onto another exercise\'s name is refused', () async {
      await create('Zercher squat');
      final second = (await repository.createCustom(
        name: 'Anderson squat',
        pattern: MovementPattern.squat,
        bodySection: BodySection.legs,
        loadType: LoadType.barbell,
      )).dataOrNull!;

      final result = await repository.renameCustom(
        id: second.id,
        name: 'Zercher squat',
      );

      expect(result.failureOrNull, isA<ParseFailure>());
    });

    test('renaming an exercise to its own name is allowed', () async {
      final created = (await repository.createCustom(
        name: 'Zercher squat',
        pattern: MovementPattern.squat,
        bodySection: BodySection.legs,
        loadType: LoadType.barbell,
      )).dataOrNull!;

      // Re-filing without touching the name must not collide with itself.
      final result = await repository.renameCustom(
        id: created.id,
        name: 'Zercher squat',
        bodySection: BodySection.core,
      );

      expect(result.failureOrNull, isNull);
      expect(
        (await repository.findById(created.id)).dataOrNull!.bodySection,
        BodySection.core,
      );
    });

    test('a seeded exercise cannot be renamed', () async {
      final result = await repository.renameCustom(
        id: systemExerciseId('exBackSquat'),
        name: 'My squat',
      );

      // Its name is an ARB key every locale resolves; renaming it here would
      // relabel the movement across everyone's history.
      expect(result.failureOrNull, isA<ParseFailure>());
      expect(
        (await repository.findById(
          systemExerciseId('exBackSquat'),
        )).dataOrNull!.nameKey,
        'exBackSquat',
      );
    });
  });

  test('a created exercise comes back as an entity', () async {
    final result = await repository.createCustom(
      name: 'Zercher squat',
      pattern: MovementPattern.squat,
      bodySection: BodySection.legs,
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
