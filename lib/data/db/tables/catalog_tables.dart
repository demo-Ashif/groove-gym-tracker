import 'package:drift/drift.dart';

import '../../../domain/enums/training_enums.dart';
import 'sync_columns.dart';

/// The canonical exercise catalog — **the single most important table**
/// (ADR §4.3).
///
/// Every set ever logged points here, which is what lets "RDL over 10 weeks"
/// survive across programs, phases, template edits and renamings. Nothing in
/// this table is ever hard-deleted for that reason.
@TableIndex(
  name: 'idx_exercises_owner_updated',
  columns: {#ownerId, #updatedAt},
)
@TableIndex(
  name: 'idx_exercises_owner_deleted',
  columns: {#ownerId, #deletedAt},
)
@DataClassName('ExerciseRow')
class Exercises extends Table with SyncedRow {
  /// Translation key for seeded system exercises (`exRomanianDeadlift`), so
  /// the catalog localizes for free (ADR §12.4). Null for user-created rows.
  TextColumn get nameKey => text().nullable()();

  /// Literal text for user-created exercises, in whatever language the user
  /// typed. Never translated — it is their own words. Null for system rows.
  TextColumn get customName => text().nullable()();

  /// JSON array of alternate spellings. The plan parser writes to this on
  /// every confirmed match, so the catalog gets smarter with each import
  /// (ADR §7.3).
  TextColumn get aliases => text().withDefault(const Constant('[]'))();

  TextColumn get pattern => textEnum<MovementPattern>()();

  TextColumn get loadType => textEnum<LoadType>()();

  /// Worked one side at a time. Drives whether the logger offers left/right
  /// rows and how tonnage is counted.
  BoolColumn get isUnilateral => boolean().withDefault(const Constant(false))();

  /// JSON array of muscle keys.
  TextColumn get primaryMuscles => text().withDefault(const Constant('[]'))();

  /// True for seeded rows. A system exercise may be hidden but not edited —
  /// otherwise one device's rename would rewrite history everywhere.
  BoolColumn get isSystem => boolean().withDefault(const Constant(false))();

  @override
  List<String> get customConstraints => [
    // Exactly one naming strategy per row (ADR §12.4). Without this a row
    // with neither name renders as blank text somewhere deep in a chart
    // legend, months later.
    'CHECK ((name_key IS NOT NULL) <> (custom_name IS NOT NULL))',
  ];
}
