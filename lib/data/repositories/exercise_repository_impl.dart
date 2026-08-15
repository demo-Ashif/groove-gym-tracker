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
    required LoadType loadType,
    bool isUnilateral = false,
    List<String> primaryMuscles = const [],
    List<String> aliases = const [],
  }) {
    return Result.guard(() async {
      final trimmed = name.trim();
      if (trimmed.isEmpty) {
        throw const ParseException('Exercise name cannot be empty');
      }

      final id = await _dao.createCustom(
        name: trimmed,
        pattern: pattern,
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
  Future<Result<void>> addAlias({
    required String exerciseId,
    required String alias,
  }) => Result.guard(() => _dao.addAlias(exerciseId, alias));

  @override
  Future<Result<void>> hide(String id) => Result.guard(() => _dao.hide(id));

  List<Exercise> _toEntities(List<ExerciseRow> rows) =>
      rows.map((row) => row.toEntity()).toList(growable: false);
}
