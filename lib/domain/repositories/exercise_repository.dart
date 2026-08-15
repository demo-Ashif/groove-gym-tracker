import '../../core/error/result.dart';
import '../entities/exercise.dart';
import '../enums/training_enums.dart';

/// The exercise catalog, as the rest of the app sees it.
///
/// Reads that a screen watches are plain `Stream`s: they come straight off a
/// Drift query, so a chart or picker recomputes itself on write with nobody
/// wiring a refresh. Writes return [Result] because they can fail and the
/// caller has to decide what to say about it.
abstract interface class ExerciseRepository {
  /// Live catalog, soft-deleted rows excluded, ordered by movement pattern.
  Stream<List<Exercise>> watchCatalog();

  Stream<List<Exercise>> watchByPattern(MovementPattern pattern);

  /// Null when the id is unknown — an id from a newer device that hasn't
  /// synced yet, or a row purged after 90 days.
  Future<Result<Exercise?>> findById(String id);

  /// Matches literal names and aliases, for the plan parser's exercise
  /// resolution (ADR §7.3). Does not match seeded names: those are ARB keys,
  /// and only the presentation layer can resolve them for the active locale.
  Future<Result<List<Exercise>>> findByText(String query);

  Future<Result<Exercise>> createCustom({
    required String name,
    required MovementPattern pattern,
    required LoadType loadType,
    bool isUnilateral,
    List<String> primaryMuscles,
    List<String> aliases,
  });

  /// Teaches the catalog a spelling the parser should recognise next time.
  Future<Result<void>> addAlias({
    required String exerciseId,
    required String alias,
  });

  /// Hides an exercise from pickers. Never a hard delete: every set ever
  /// logged points here.
  Future<Result<void>> hide(String id);
}
