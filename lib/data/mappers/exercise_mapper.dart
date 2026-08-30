import 'dart:convert';

import '../../core/logging/app_logger.dart';
import '../../domain/entities/exercise.dart';
import '../db/app_database.dart';

/// Row → entity. The other direction is expressed as companions at the DAO,
/// because a partial update has no entity to build from.
extension ExerciseRowMapper on ExerciseRow {
  Exercise toEntity() => Exercise(
    id: id,
    nameKey: nameKey,
    customName: customName,
    aliases: _decodeStringList(aliases, field: 'aliases', rowId: id),
    pattern: pattern,
    bodySection: bodySection,
    loadType: loadType,
    isUnilateral: isUnilateral,
    primaryMuscles: _decodeStringList(
      primaryMuscles,
      field: 'primary_muscles',
      rowId: id,
    ),
    isSystem: isSystem,
    isHidden: deletedAt != null,
  );
}

/// JSON columns are the one place a schema this typed can still hand you
/// rubbish — a row written by a newer client, or a bad hand-edit during
/// debugging. Log it and carry on with an empty list: a missing alias makes
/// the parser slightly worse, while throwing here takes out the whole catalog
/// query and with it the screen.
List<String> _decodeStringList(
  String raw, {
  required String field,
  required String rowId,
}) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return decoded.whereType<String>().toList(growable: false);
  } on FormatException catch (error) {
    AppLogger.w('Malformed $field on exercise $rowId: $error', tag: 'DB');
    return const [];
  }
}
