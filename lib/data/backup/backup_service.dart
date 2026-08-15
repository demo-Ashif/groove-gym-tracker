import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/error/app_exception.dart';
import '../../core/logging/app_logger.dart';
import '../db/app_database.dart';

/// A parsed backup, before anything is written.
class BackupPreview {
  const BackupPreview({
    required this.schemaVersion,
    required this.exportedAt,
    required this.rowCounts,
  });

  final int schemaVersion;
  final DateTime? exportedAt;

  /// Table name → row count, for the confirmation screen. Restoring is
  /// destructive, so the user gets to see what they are about to swap in.
  final Map<String, int> rowCounts;

  int get totalRows => rowCounts.values.fold(0, (sum, count) => sum + count);
}

/// Full local JSON export and restore (ADR §18).
///
/// **This is a first-class feature, not a fallback.** Supabase is not a backup
/// strategy on its own: a bad migration or an RLS mistake propagates to the
/// server too. A file the user holds is the only copy that cannot be broken
/// from the other end.
///
/// The format is a straight relational dump — every table, every column, no
/// interpretation — so a future version can read an old file without needing
/// this version's code, and a human can open it in a text editor and see their
/// training.
class BackupService {
  const BackupService(this._db);

  final AppDatabase _db;

  /// Bumped when the *file* format changes, which is not the same as the
  /// database schema changing. Restoring checks this before touching anything.
  static const formatVersion = 1;

  static const _tablesKey = 'tables';
  static const _schemaKey = 'schemaVersion';
  static const _formatKey = 'formatVersion';
  static const _exportedAtKey = 'exportedAt';

  /// Tables written to, and read from, a backup.
  ///
  /// The outbox is deliberately absent: it is this device's queue of unsent
  /// intent, not data, and restoring one device's queue onto another would
  /// replay writes that already happened.
  List<TableInfo<Table, dynamic>> get _tables => [
    _db.exercises,
    _db.programs,
    _db.phases,
    _db.sessionTemplates,
    _db.blockTemplates,
    _db.exerciseTemplates,
    _db.scheduledSessions,
    _db.sessionLogs,
    _db.setLogs,
    _db.prs,
    _db.checkIns,
    _db.metricDefinitions,
  ];

  /// Everything, as pretty-printed JSON.
  Future<String> export() async {
    final tables = <String, List<Map<String, Object?>>>{};

    for (final table in _tables) {
      final rows = await _db
          .customSelect(
            'SELECT * FROM ${table.actualTableName}',
            readsFrom: {table},
          )
          .get();

      tables[table.actualTableName] = rows
          .map((row) => _encodeRow(row.data))
          .toList(growable: false);
    }

    return const JsonEncoder.withIndent('  ').convert({
      _formatKey: formatVersion,
      _schemaKey: _db.schemaVersion,
      _exportedAtKey: DateTime.now().toIso8601String(),
      _tablesKey: tables,
    });
  }

  /// Reads a backup without writing anything.
  ///
  /// Restoring replaces the database, so the user sees the shape of the file
  /// first. A malformed file fails here, before any rows have been touched.
  BackupPreview preview(String json) {
    final decoded = _decode(json);
    final tables = decoded[_tablesKey];

    if (tables is! Map) {
      throw const ParseException('Backup has no tables');
    }

    return BackupPreview(
      schemaVersion: switch (decoded[_schemaKey]) {
        final int version => version,
        _ => 0,
      },
      exportedAt: switch (decoded[_exportedAtKey]) {
        final String raw => DateTime.tryParse(raw),
        _ => null,
      },
      rowCounts: {
        for (final entry in tables.entries)
          if (entry.value is List) '${entry.key}': (entry.value as List).length,
      },
    );
  }

  /// Replaces local data with the backup's, in **one transaction**.
  ///
  /// All-or-nothing on purpose: a half-restored database is worse than either
  /// the old data or the new. If anything in the file is unreadable, the
  /// transaction rolls back and the user still has what they had.
  ///
  /// Rows are inserted with their original ids, which is what makes a restore
  /// idempotent and keeps a restored device in agreement with the server.
  Future<int> restore(String json) async {
    final decoded = _decode(json);
    final tables = decoded[_tablesKey];
    if (tables is! Map) {
      throw const ParseException('Backup has no tables');
    }

    final fileSchema = switch (decoded[_schemaKey]) {
      final int version => version,
      _ => 0,
    };
    if (fileSchema > _db.schemaVersion) {
      // Written by a newer build. Guessing at columns this version doesn't
      // know would drop data silently.
      throw const ParseException('Backup is from a newer version of Groove');
    }

    var restored = 0;

    await _db.transaction(() async {
      // Foreign keys are checked per statement, and a dump's row order does
      // not respect them — a set log can appear before its session. Deferring
      // the check to the end of the transaction still catches a genuinely
      // broken file, just at commit rather than mid-insert.
      await _db.customStatement('PRAGMA defer_foreign_keys = ON');

      // Reverse order: children first, so nothing is orphaned mid-wipe.
      for (final table in _tables.reversed) {
        await _db.customStatement('DELETE FROM ${table.actualTableName}');
      }

      for (final table in _tables) {
        final rows = tables[table.actualTableName];
        if (rows is! List) continue;

        for (final row in rows) {
          if (row is! Map) continue;
          restored += await _insertRow(table, row);
        }
      }
    });

    AppLogger.i('Restored $restored rows from backup', tag: 'BACKUP');
    return restored;
  }

  Future<int> _insertRow(
    TableInfo<Table, dynamic> table,
    Map<Object?, Object?> row,
  ) async {
    // Only columns this build knows about. A file from an older version is
    // missing some; a hand-edited one may have extras. Both are survivable.
    final columns = {for (final column in table.$columns) column.name: column};
    final present = row.keys
        .map((key) => '$key')
        .where(columns.containsKey)
        .toList();

    if (present.isEmpty) return 0;

    final values = <String, Variable<Object>>{
      for (final name in present) name: _variableFor(columns[name]!, row[name]),
    };

    // A raw INSERT bypasses drift's companions, so a column's client default
    // never fires. Filling them here is what lets an older or hand-edited
    // backup — one written before `updated_at` existed, say — restore instead
    // of failing on a NOT NULL constraint.
    for (final column in table.$columns) {
      if (values.containsKey(column.name) || column.$nullable) continue;

      final clientDefault = column.clientDefault;
      if (clientDefault == null) continue;

      values[column.name] = _variableFor(column, clientDefault());
    }

    final names = values.keys.toList();
    final placeholders = List.filled(names.length, '?').join(', ');
    await _db.customInsert(
      'INSERT OR REPLACE INTO ${table.actualTableName} '
      '(${names.join(', ')}) VALUES ($placeholders)',
      variables: [for (final name in names) values[name]!],
      updates: {table},
    );
    return 1;
  }

  /// Values come back from JSON as strings, numbers or null; the column decides
  /// how to read them.
  Variable<Object> _variableFor(GeneratedColumn<Object> column, Object? value) {
    if (value == null) return const Variable<String>(null);

    return switch (column.type) {
      DriftSqlType.bool => Variable<bool>(
        // JSON may carry a real bool, or the 0/1 SQLite stored.
        value is bool ? value : value == 1 || value == '1',
      ),
      DriftSqlType.int => Variable<int>(
        value is int ? value : int.tryParse('$value'),
      ),
      DriftSqlType.double => Variable<double>(
        value is num ? value.toDouble() : double.tryParse('$value'),
      ),
      _ => Variable<String>('$value'),
    };
  }

  Map<String, Object?> _encodeRow(Map<String, Object?> data) => {
    for (final entry in data.entries)
      // Drift hands back `Uint8List` for blob columns; nothing in this schema
      // uses one, but a dump that silently dropped a column would be a quiet
      // way to lose data, so anything unexpected is stringified rather than
      // skipped.
      entry.key: switch (entry.value) {
        null || bool() || num() || String() => entry.value,
        final other => other.toString(),
      },
  };

  Map<String, Object?> _decode(String json) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is! Map<String, Object?>) {
        throw const ParseException('Backup is not a Groove export');
      }
      return decoded;
    } on FormatException catch (error) {
      throw ParseException('Backup is not valid JSON: ${error.message}');
    }
  }
}
