import 'dart:convert';

import '../../core/logging/app_logger.dart';
import '../../domain/enums/training_enums.dart';
import '../../domain/values/schedule_pattern.dart';

/// JSON ↔ [SchedulePattern].
///
/// A `type` discriminator is stored rather than inferred from shape, so a
/// cadence can be added later without the old payloads becoming ambiguous.
/// Weekday keys are strings because JSON object keys always are.
abstract final class SchedulePatternCodec {
  static String? encode(SchedulePattern? pattern) => switch (pattern) {
    null => null,
    WeeklyPattern(:final days) => jsonEncode({
      'type': 'weekly',
      'days': {
        for (final entry in days.entries)
          entry.key.toString(): _encodeAssignment(entry.value),
      },
    }),
    CyclePattern(:final days) => jsonEncode({
      'type': 'cycle',
      'days': days.map(_encodeAssignment).toList(),
    }),
  };

  /// Returns null for anything unreadable — a missing column, malformed JSON,
  /// or a cadence written by a newer client.
  ///
  /// Null means "no schedule committed yet", which the editor already knows
  /// how to render. Guessing at a half-understood pattern would silently
  /// materialize the wrong calendar, which is far worse than asking the user
  /// to redraw the strip.
  static SchedulePattern? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;

    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return null;

      return switch (json['type']) {
        'weekly' => _decodeWeekly(json['days']),
        'cycle' => _decodeCycle(json['days']),
        _ => null,
      };
    } on FormatException catch (error) {
      AppLogger.w('Malformed schedule pattern: $error', tag: 'DB');
      return null;
    }
  }

  static SchedulePattern? _decodeWeekly(Object? raw) {
    if (raw is! Map) return null;

    final days = <int, DayAssignment>{};
    for (final entry in raw.entries) {
      final weekday = int.tryParse('${entry.key}');
      // Out-of-range weekdays would never match a real day, so they are
      // dropped rather than carried forward as dead entries.
      if (weekday == null ||
          weekday < DateTime.monday ||
          weekday > DateTime.sunday) {
        continue;
      }

      final assignment = _decodeAssignment(entry.value);
      if (assignment != null) days[weekday] = assignment;
    }

    return SchedulePattern.weekly(days);
  }

  static SchedulePattern? _decodeCycle(Object? raw) {
    if (raw is! List) return null;

    final days = raw
        .map(_decodeAssignment)
        .whereType<DayAssignment>()
        .toList(growable: false);

    return SchedulePattern.cycle(days);
  }

  static Map<String, Object?> _encodeAssignment(DayAssignment assignment) => {
    'kind': assignment.kind.name,
    'code': ?assignment.sessionCode,
  };

  static DayAssignment? _decodeAssignment(Object? raw) {
    if (raw is! Map) return null;

    final kind = ScheduledSessionKind.values.firstWhere(
      (value) => value.name == raw['kind'],
      orElse: () => ScheduledSessionKind.rest,
    );

    return switch (kind) {
      ScheduledSessionKind.gym => switch (raw['code']) {
        final String code when code.isNotEmpty => DayAssignment.gym(code),
        // A gym day with no code cannot be resolved to a session; rest is the
        // honest reading.
        _ => const DayAssignment.rest(),
      },
      ScheduledSessionKind.rest => const DayAssignment.rest(),
      ScheduledSessionKind.cricket => const DayAssignment.cricket(),
      ScheduledSessionKind.custom => const DayAssignment.custom(),
    };
  }
}
