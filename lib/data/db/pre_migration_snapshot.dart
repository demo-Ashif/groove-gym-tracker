import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/logging/app_logger.dart';

/// Where a snapshot is written. Injectable so tests — and a future restore
/// screen — do not have to touch the real documents directory.
typedef SnapshotSink = Future<void> Function(String fileName, String contents);

/// A full copy of the database, taken **before** a schema migration runs.
///
/// The migrations themselves are non-destructive by contract, but "the
/// migration was wrong" is the one bug that cannot be undone once it has run:
/// it rewrites the only copy of data that exists on the device. This is the
/// undo. Supabase is not a backup strategy on its own and there is no backend
/// yet at all, so this file is the whole safety net (ADR §18).
///
/// Read entirely through `sqlite_master` and `SELECT *`, with no reference to
/// any generated table class, because it has to run against the *old* schema —
/// whatever shape that was, including versions this build has never seen.
class PreMigrationSnapshot {
  const PreMigrationSnapshot(this._executor, {SnapshotSink? sink})
    : _sink = sink;

  final DatabaseConnectionUser _executor;
  final SnapshotSink? _sink;

  /// How many snapshots to keep. Enough to survive a bad upgrade that is only
  /// noticed a release later, few enough not to grow without bound.
  static const keepNewest = 3;

  static const filePrefix = 'groove_pre_migration_v';

  /// Writes the snapshot and returns its file name, or null if it could not be
  /// written.
  ///
  /// Never throws. A failed backup must not stop a user opening their app —
  /// the migration that follows preserves data on its own, and this is the
  /// belt to its braces.
  Future<String?> capture({
    required int fromVersion,
    required int toVersion,
    DateTime? at,
  }) async {
    try {
      final timestamp = (at ?? DateTime.now()).toUtc().toIso8601String();
      final payload = jsonEncode({
        'schemaVersion': fromVersion,
        'upgradingTo': toVersion,
        'capturedAt': timestamp,
        'tables': await _dumpTables(),
      });

      // Colons are legal in a POSIX filename and illegal on Windows; strip
      // them so the same name works if this ever runs on desktop.
      final fileName =
          '$filePrefix$fromVersion'
          '_${timestamp.replaceAll(RegExp('[:.]'), '-')}.json';

      await (_sink ?? _writeToDocuments)(fileName, payload);
      AppLogger.i('Pre-migration snapshot written: $fileName', tag: 'DB');
      return fileName;
    } catch (error) {
      AppLogger.e(
        'Pre-migration snapshot failed; continuing with the migration',
        error: error,
        tag: 'DB',
      );
      return null;
    }
  }

  Future<Map<String, List<Map<String, Object?>>>> _dumpTables() async {
    final tables = await _executor
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'android_%' "
          'ORDER BY name',
        )
        .get();

    final dump = <String, List<Map<String, Object?>>>{};
    for (final table in tables) {
      final name = table.read<String>('name');
      // Quoted, because a table name is an identifier from the database
      // rather than from this source file.
      final rows = await _executor
          .customSelect('SELECT * FROM "${name.replaceAll('"', '""')}"')
          .get();

      dump[name] = [for (final row in rows) _encodeRow(row.data)];
    }
    return dump;
  }

  /// SQLite hands back strings, ints, doubles, nulls and blobs. Only the last
  /// is not JSON, so it goes out as base64.
  Map<String, Object?> _encodeRow(Map<String, Object?> row) {
    return {
      for (final entry in row.entries)
        entry.key: switch (entry.value) {
          final Uint8List bytes => {'base64': base64Encode(bytes)},
          final value => value,
        },
    };
  }

  static Future<void> _writeToDocuments(
    String fileName,
    String contents,
  ) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/$fileName');
    await file.writeAsString(contents, flush: true);

    await _pruneOldSnapshots(directory);
  }

  static Future<void> _pruneOldSnapshots(Directory directory) async {
    final snapshots =
        directory
            .listSync()
            .whereType<File>()
            .where((file) => file.uri.pathSegments.last.startsWith(filePrefix))
            .toList()
          // Newest first: the file name carries an ISO timestamp, which sorts
          // in exactly chronological order.
          ..sort((a, b) => b.path.compareTo(a.path));

    for (final stale in snapshots.skip(keepNewest)) {
      await stale.delete();
    }
  }
}
