import 'package:drift/drift.dart';

import '../../../domain/enums/training_enums.dart';
import 'sync_columns.dart';

/// The outbox (ADR §4.3, §6).
///
/// **Local only** — it is never synced, and deliberately does *not* use
/// [SyncedRow]: it has no owner, no soft delete and nothing to reconcile. It
/// is this device's queue of intent.
///
/// The rule that makes it correct: **the outbox write happens in the same
/// SQLite transaction as the data write** (ADR §6.2 rule 1). A crash between
/// the two would otherwise silently drop a set.
@TableIndex(name: 'idx_sync_outbox_created', columns: {#createdAt})
@DataClassName('OutboxRow')
class SyncOutbox extends Table {
  TextColumn get id => text().clientDefault(newRowId)();

  /// Target table, in its Postgres (snake_case) spelling. Named explicitly
  /// because `tableName` is taken by drift's own [Table] API.
  TextColumn get targetTable => text().named('table_name')();

  TextColumn get rowId => text()();

  TextColumn get op => textEnum<OutboxOp>()();

  /// JSON body to upsert. Snapshotted at enqueue time rather than re-read at
  /// push time, so a push replays what the user actually did.
  TextColumn get payload => text()();

  /// Backoff bookkeeping. After 10 failures the row is marked as needing
  /// attention and surfaced in Settings rather than retried forever
  /// (ADR §6.2 rule 6).
  IntColumn get attemptCount => integer().withDefault(const Constant(0))();

  TextColumn get lastError => text().nullable()();

  DateTimeColumn get createdAt => dateTime().clientDefault(DateTime.now)();

  /// When the next attempt becomes eligible — exponential backoff with
  /// jitter, 2s → 4s → … → 5min cap.
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
