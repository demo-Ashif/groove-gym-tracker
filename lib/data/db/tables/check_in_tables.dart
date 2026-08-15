import 'package:drift/drift.dart';

import '../../../domain/enums/training_enums.dart';
import 'plan_tables.dart';
import 'sync_columns.dart';

/// Check-ins and the user-configurable fields they render (ADR §10).

@TableIndex(name: 'idx_check_ins_date', columns: {#date})
@DataClassName('CheckInRow')
class CheckIns extends Table with SyncedRow {
  /// Nullable so a check-in can outlive the program it was taken during —
  /// body-weight history is the one series that must never break at a program
  /// boundary.
  TextColumn get programId => text()
      .references(Programs, #id, onDelete: KeyAction.setNull)
      .nullable()();

  TextColumn get phaseId =>
      text().references(Phases, #id, onDelete: KeyAction.setNull).nullable()();

  /// Date-only `YYYY-MM-DD`.
  TextColumn get date => text().withLength(min: 10, max: 10)();

  RealColumn get weightKg => real().nullable()();

  RealColumn get waistCm => real().nullable()();

  /// JSON map of `metric_definitions.key` → value, so adding a tracked field
  /// is a row in that table rather than a schema migration here.
  TextColumn get extra => text().withDefault(const Constant('{}'))();

  /// JSON array of **relative** paths inside the app's documents directory.
  /// Never absolute — an iOS container path changes between builds and a
  /// stored absolute path is a broken image after the next install
  /// (ADR §18).
  TextColumn get photoRefs => text().withDefault(const Constant('[]'))();

  TextColumn get notes => text().nullable()();
}

/// Which fields a check-in asks for. Driven by data so the form stays two or
/// three fields long instead of growing a settings maze (ADR §10.2).
@TableIndex(name: 'idx_metric_definitions_order', columns: {#orderIndex})
@DataClassName('MetricDefinitionRow')
class MetricDefinitions extends Table with SyncedRow {
  /// Stable identifier used as the key inside `check_ins.extra`. Never
  /// translated, never shown.
  TextColumn get key => text()();

  /// ARB key for seeded metrics, literal text for user-added ones — the same
  /// key-or-literal split the exercise catalog uses (ADR §12.4).
  TextColumn get labelKey => text()();

  /// Unit symbol (`kg`, `cm`). Rendered through `intl`, not concatenated.
  TextColumn get unit => text().nullable()();

  TextColumn get inputType => textEnum<MetricInputType>()();

  BoolColumn get isEnabled => boolean().withDefault(const Constant(true))();

  IntColumn get orderIndex => integer()();
}
