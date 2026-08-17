import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../domain/enums/training_enums.dart';
import '../app_database.dart';
import '../tables/catalog_tables.dart';

part 'exercise_dao.g.dart';

/// Reads and writes the exercise catalog.
///
/// Every query filters out soft-deleted rows. A hidden exercise still has to
/// exist — set logs point at it and charts read through it — so "deleted"
/// here only ever means "don't offer it in the picker".
@DriftAccessor(tables: [Exercises])
class ExerciseDao extends DatabaseAccessor<AppDatabase>
    with _$ExerciseDaoMixin {
  ExerciseDao(super.attachedDatabase);

  /// Live catalog. A `Stream` rather than a future because the picker has to
  /// pick up an exercise created from the plan-import screen without anyone
  /// wiring a refresh.
  Stream<List<ExerciseRow>> watchCatalog() {
    return (select(exercises)
          ..where((row) => row.deletedAt.isNull())
          ..orderBy([
            (row) => OrderingTerm(expression: row.bodySection),
            (row) => OrderingTerm(expression: row.isSystem),
          ]))
        .watch();
  }

  Stream<List<ExerciseRow>> watchByPattern(MovementPattern pattern) {
    return (select(exercises)..where(
          (row) => row.deletedAt.isNull() & row.pattern.equalsValue(pattern),
        ))
        .watch();
  }

  Future<ExerciseRow?> findById(String id) {
    return (select(
      exercises,
    )..where((row) => row.id.equals(id))).getSingleOrNull();
  }

  /// Alias and literal-name lookup for the plan parser's matcher (ADR §7.3).
  ///
  /// Deliberately does *not* search `nameKey`: that is an ARB key, not text a
  /// user ever types. Matching display names is the presentation layer's job,
  /// because only it can resolve them for the active locale.
  Future<List<ExerciseRow>> findByText(String query) {
    final needle = '%${query.trim().toLowerCase()}%';
    return (select(exercises)..where(
          (row) =>
              row.deletedAt.isNull() &
              (row.customName.lower().like(needle) |
                  row.aliases.lower().like(needle)),
        ))
        .get();
  }

  Future<int> countActive() async {
    final count = exercises.id.count();
    final query = selectOnly(exercises)
      ..addColumns([count])
      ..where(exercises.deletedAt.isNull());
    return await query.map((row) => row.read(count)).getSingle() ?? 0;
  }

  /// Creates a user-defined exercise. Literal text, never a key — it is the
  /// user's own language and is never translated (ADR §12.4).
  Future<String> createCustom({
    required String name,
    required MovementPattern pattern,
    required BodySection bodySection,
    required LoadType loadType,
    bool isUnilateral = false,
    List<String> primaryMuscles = const [],
    List<String> aliases = const [],
  }) async {
    final row = await into(exercises).insertReturning(
      ExercisesCompanion.insert(
        customName: Value(name.trim()),
        pattern: pattern,
        bodySection: bodySection,
        loadType: loadType,
        isUnilateral: Value(isUnilateral),
        primaryMuscles: Value(jsonEncode(primaryMuscles)),
        aliases: Value(jsonEncode(aliases)),
      ),
    );
    return row.id;
  }

  /// Renames a user-created exercise and optionally re-files it.
  ///
  /// System rows are untouchable by design: their name is an ARB key that
  /// every locale resolves, and one device's rename would relabel the same
  /// movement in everyone's history (ADR §12.4).
  Future<void> updateCustom({
    required String id,
    required String name,
    BodySection? bodySection,
  }) async {
    await (update(
      exercises,
    )..where((row) => row.id.equals(id) & row.isSystem.equals(false))).write(
      ExercisesCompanion(
        customName: Value(name.trim()),
        bodySection: bodySection == null
            ? const Value.absent()
            : Value(bodySection),
        updatedAt: Value(DateTime.now()),
        syncState: const Value(SyncState.pendingUpdate),
      ),
    );
  }

  /// A live custom exercise whose name matches, case- and whitespace-
  /// insensitively. [excludingId] lets a rename ignore the row being renamed.
  ///
  /// Only searches `custom_name`: a seeded row's name is an ARB key, so SQL
  /// cannot compare it against typed text. Collisions with system names are
  /// caught in the presentation layer, which is the only place that can
  /// resolve them for the active locale.
  Future<ExerciseRow?> findCustomByName(
    String name, {
    String? excludingId,
  }) async {
    final needle = name.trim().toLowerCase();
    if (needle.isEmpty) return null;

    return (select(exercises)..where((row) {
          final match =
              row.deletedAt.isNull() & row.customName.lower().equals(needle);
          return excludingId == null
              ? match
              : match & row.id.equals(excludingId).not();
        }))
        .getSingleOrNull();
  }

  /// Records a confirmed match so the catalog gets smarter with every import
  /// (ADR §7.3). No-ops on a duplicate rather than growing the list.
  Future<void> addAlias(String exerciseId, String alias) async {
    await transaction(() async {
      final row = await findById(exerciseId);
      if (row == null) return;

      final current = (jsonDecode(row.aliases) as List).cast<String>();
      final trimmed = alias.trim();
      if (trimmed.isEmpty ||
          current.any((a) => a.toLowerCase() == trimmed.toLowerCase())) {
        return;
      }

      await (update(exercises)..where((r) => r.id.equals(exerciseId))).write(
        ExercisesCompanion(
          aliases: Value(jsonEncode([...current, trimmed])),
          updatedAt: Value(DateTime.now()),
          syncState: const Value(SyncState.pendingUpdate),
        ),
      );
    });
  }

  /// Soft delete only (ADR §6.2 rule 5). A hard delete could not propagate,
  /// and would be blocked by the `restrict` foreign key from `set_logs`
  /// anyway — which is the schema saying the same thing.
  Future<void> hide(String id) async {
    await (update(exercises)..where((row) => row.id.equals(id))).write(
      ExercisesCompanion(
        deletedAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
        syncState: const Value(SyncState.pendingDelete),
      ),
    );
  }
}
