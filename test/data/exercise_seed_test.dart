import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:groove/data/db/app_database.dart';
import 'package:groove/data/db/seed/exercise_seed.dart';
import 'package:groove/domain/enums/training_enums.dart';
import 'package:groove/l10n/generated/app_localizations.dart';
import 'package:groove/shared/l10n/exercise_name.dart';

/// Guards the three artifacts generated from one source list — the seed, the
/// ARB entries and the resolver switch.
///
/// Without this, a half-added exercise ships quietly and surfaces months later
/// as a blank row in a chart legend, which is exactly the failure mode ARB
/// keys are supposed to prevent.
void main() {
  final l10n = lookupL10n(const Locale('en'));

  test('every seeded exercise resolves to a real name', () {
    for (final exercise in exerciseCatalogSeed) {
      final name = exerciseDisplayName(l10n: l10n, nameKey: exercise.nameKey);

      expect(name, isNotEmpty, reason: exercise.nameKey);
      // The resolver falls back to echoing the key it doesn't know; if that
      // happens here, the ARB entry or the switch case is missing.
      expect(
        name,
        isNot(exercise.nameKey),
        reason: 'No ARB entry or resolver case for ${exercise.nameKey}',
      );
    }
  });

  test('every seeded exercise files under a real body section', () {
    // `fullBody` is the derivation's fallback for a muscle it doesn't know, so
    // a row landing there unexpectedly means the muscle list gained a key the
    // mapping never learned — and the picker quietly buries the exercise.
    final unclassified = <String>[];

    for (final exercise in exerciseCatalogSeed) {
      final section = BodySection.forExercise(
        pattern: exercise.pattern,
        primaryMuscles: exercise.primaryMuscles,
      );

      if (section == BodySection.fullBody &&
          exercise.primaryMuscles.isNotEmpty &&
          exercise.primaryMuscles.first != 'fullBody') {
        unclassified.add('${exercise.nameKey} -> ${exercise.primaryMuscles}');
      }
    }

    expect(
      unclassified,
      isEmpty,
      reason: 'muscles with no section mapping:\n${unclassified.join('\n')}',
    );
  });

  test('conditioning and mobility file by pattern, not by muscle', () {
    // A treadmill's `legs` is true, but filing it beside squats is not what
    // anyone searching the picker is looking for.
    expect(
      BodySection.forExercise(
        pattern: MovementPattern.conditioning,
        primaryMuscles: const ['legs'],
      ),
      BodySection.cardio,
    );
    expect(
      BodySection.forExercise(
        pattern: MovementPattern.mobility,
        primaryMuscles: const ['spine'],
      ),
      BodySection.mobility,
    );
  });

  test('name keys and derived ids are unique', () {
    final keys = exerciseCatalogSeed.map((e) => e.nameKey).toList();
    final ids = keys.map(systemExerciseId).toSet();

    expect(keys.toSet(), hasLength(keys.length), reason: 'duplicate name key');
    expect(ids, hasLength(keys.length), reason: 'v5 id collision');
  });

  test('every name key uses the ex-prefixed convention', () {
    for (final exercise in exerciseCatalogSeed) {
      expect(exercise.nameKey, startsWith('ex'), reason: exercise.nameKey);
    }
  });

  test('the catalog covers every movement pattern', () {
    final covered = exerciseCatalogSeed.map((e) => e.pattern).toSet();

    // A pattern with no exercises would render an empty group in the picker
    // and a permanently flat series in the volume-by-pattern chart.
    expect(covered, containsAll(MovementPattern.values));
  });

  test('user-typed text resolves to itself, untranslated', () {
    // A user-created exercise is in the user's own language and must never be
    // run through ARB (ADR §12.4).
    expect(
      exerciseDisplayName(l10n: l10n, customName: 'Zercher squat'),
      'Zercher squat',
    );
    // Literal text wins even if a key is somehow also present.
    expect(
      exerciseDisplayName(
        l10n: l10n,
        nameKey: 'exBackSquat',
        customName: 'My squat',
      ),
      'My squat',
    );
  });

  test('an unknown key echoes rather than rendering blank', () {
    // A row synced from a device running a newer build. Showing the raw key
    // is ugly; showing nothing is a bug report.
    expect(
      exerciseDisplayName(l10n: l10n, nameKey: 'exFromTheFuture'),
      'exFromTheFuture',
    );
  });

  test('loadable types are the ones e1RM is charted from', () {
    // e1RM only means something with an external load (ADR §4.4).
    expect(LoadType.barbell.isLoadable, isTrue);
    expect(LoadType.bodyweight.isLoadable, isFalse);
    expect(LoadType.time.isLoadable, isFalse);

    // Dumbbells are logged per hand, so tonnage counts both.
    expect(LoadType.dumbbellPerHand.tonnageMultiplier, 2);
    expect(LoadType.barbell.tonnageMultiplier, 1);
  });
}
