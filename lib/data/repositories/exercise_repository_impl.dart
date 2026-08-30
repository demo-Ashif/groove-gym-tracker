import '../../core/error/app_exception.dart';
import '../../core/error/result.dart';
import '../../domain/entities/exercise.dart';
import '../../domain/enums/training_enums.dart';
import '../../domain/repositories/exercise_repository.dart';
import '../db/app_database.dart';
import '../db/daos/exercise_dao.dart';
import '../mappers/exercise_mapper.dart';

/// Drift-backed catalog. The only class in the app that knows the catalog is
/// SQLite — swapping the store is this file.
class ExerciseRepositoryImpl implements ExerciseRepository {
  const ExerciseRepositoryImpl(this._dao);

  final ExerciseDao _dao;

  @override
  Stream<List<Exercise>> watchCatalog() => _dao.watchCatalog().map(_toEntities);

  @override
  Stream<List<Exercise>> watchByPattern(MovementPattern pattern) =>
      _dao.watchByPattern(pattern).map(_toEntities);

  @override
  Future<Result<Exercise?>> findById(String id) =>
      Result.guard(() async => (await _dao.findById(id))?.toEntity());

  @override
  Future<Result<List<Exercise>>> findByText(String query) =>
      Result.guard(() async => _toEntities(await _dao.findByText(query)));

  @override
  Future<Result<Exercise>> createCustom({
    required String name,
    required MovementPattern pattern,
    required BodySection bodySection,
    required LoadType loadType,
    bool isUnilateral = false,
    List<String> primaryMuscles = const [],
    List<String> aliases = const [],
  }) {
    return Result.guard(() async {
      final trimmed = await _requireAvailableName(name);

      final id = await _dao.createCustom(
        name: trimmed,
        pattern: pattern,
        bodySection: bodySection,
        loadType: loadType,
        isUnilateral: isUnilateral,
        primaryMuscles: primaryMuscles,
        aliases: aliases,
      );

      final row = await _dao.findById(id);
      if (row == null) {
        // The insert reported success and the row isn't there — that is a
        // storage fault, not an empty result, and it must not surface as a
        // silent null.
        throw const CacheException('Created exercise could not be read back');
      }
      return row.toEntity();
    });
  }

  @override
  Future<Result<void>> renameCustom({
    required String id,
    required String name,
    BodySection? bodySection,
  }) {
    return Result.guard(() async {
      final existing = await _dao.findById(id);
      if (existing == null) {
        throw const CacheException('Exercise no longer exists');
      }
      if (existing.isSystem) {
        // Caught here rather than left to the DAO's silent no-op: a rename
        // that reports success and changes nothing is worse than a refusal.
        throw const ParseException('A built-in exercise cannot be renamed');
      }

      final trimmed = await _requireAvailableName(name, excludingId: id);
      await _dao.updateCustom(id: id, name: trimmed, bodySection: bodySection);
    });
  }

  @override
  Future<Result<void>> addAlias({
    required String exerciseId,
    required String alias,
  }) => Result.guard(() => _dao.addAlias(exerciseId, alias));

  @override
  Future<Result<void>> hide(String id) => Result.guard(() => _dao.hide(id));

  /// Trims, rejects blanks, and rejects a name another custom exercise already
  /// holds. Returns the trimmed name so callers store exactly what was checked.
  Future<String> _requireAvailableName(
    String name, {
    String? excludingId,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const ParseException('Exercise name cannot be empty');
    }

    final clash = await _dao.findCustomByName(
      trimmed,
      excludingId: excludingId,
    );
    if (clash != null) {
      throw const ParseException('An exercise with that name already exists');
    }

    return trimmed;
  }

  List<Exercise> _toEntities(List<ExerciseRow> rows) =>
      rows.map((row) => row.toEntity()).toList(growable: false);
}
