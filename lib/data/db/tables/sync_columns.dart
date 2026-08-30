import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../domain/enums/training_enums.dart';

const _uuid = Uuid();

/// Client-generated row id (ADR §4.2).
///
/// **v7, not v4.** Both are generated offline without waiting on a server
/// sequence, but v7 embeds a millisecond timestamp in its high bits, so ids
/// sort in creation order. That keeps B-tree inserts at the right edge of the
/// primary-key index instead of scattering them, which matters once a set is
/// being written every few seconds mid-session.
String newRowId() => _uuid.v7();

/// The universal row contract every syncable table carries, in both SQLite
/// and Postgres (ADR §4.2).
///
/// Applied as a mixin so a new table cannot quietly omit one of these — the
/// sync engine assumes all six exist on every row it touches.
mixin SyncedRow on Table {
  TextColumn get id => text().clientDefault(newRowId)();

  /// The anonymous auth user (ADR §5.1). Null until the first sign-in — the
  /// app is fully usable before any backend exists, and the sync layer
  /// stamps existing rows when an identity first appears.
  TextColumn get ownerId => text().nullable()();

  DateTimeColumn get createdAt => dateTime().clientDefault(DateTime.now)();

  /// Conflict resolution and the pull cursor both key off this
  /// (ADR §6.2 rules 3–4). Written on every mutation, never by hand.
  DateTimeColumn get updatedAt => dateTime().clientDefault(DateTime.now)();

  /// **Soft delete.** A hard delete cannot propagate to another device — the
  /// row simply reappears on the next pull (ADR §6.2 rule 5). A purge job
  /// removes these locally after 90 days.
  DateTimeColumn get deletedAt => dateTime().nullable()();

  /// Local-only. Never pushed; it describes this device's relationship to the
  /// row, not the row itself.
  TextColumn get syncState =>
      textEnum<SyncState>().withDefault(const Constant('pendingCreate'))();

  /// Forward-compat guard on sync payloads: a newer client's row can be
  /// recognised and left alone rather than misread.
  IntColumn get schemaVersion => integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {id};
}
