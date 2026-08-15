import 'dart:convert';

import '../../core/logging/app_logger.dart';
import '../../domain/values/progression_rule.dart';

/// JSON ↔ [ProgressionRule]. Lives in the data layer because the domain has no
/// opinion about serialization (ADR §3).
///
/// The `type` discriminator is stored, never inferred from which fields are
/// present — that is what lets a rule be extended without the old shape
/// becoming ambiguous.
abstract final class ProgressionRuleCodec {
  static const _type = 'type';

  /// Null for a fixed rule, so the common case stores nothing at all rather
  /// than `{"type":"fixed"}` on every row.
  static String? encode(ProgressionRule rule) {
    final json = switch (rule) {
      FixedProgression() => null,
      LinearWeeklyProgression(:final incrementKg, :final ceilingKg) => {
        _type: 'linearWeekly',
        'incrementKg': incrementKg,
        // Null-aware entry: omitted entirely when there is no ceiling.
        'ceilingKg': ?ceilingKg,
      },
      DoubleProgression(:final repsMin, :final repsMax, :final incrementKg) => {
        _type: 'doubleProgression',
        'repsMin': repsMin,
        'repsMax': repsMax,
        'incrementKg': incrementKg,
      },
      TopSetBackoffProgression(:final backoffSets, :final backoffPercent) => {
        _type: 'topSetBackoff',
        'backoffSets': backoffSets,
        'backoffPercent': backoffPercent,
      },
    };

    return json == null ? null : jsonEncode(json);
  }

  /// Falls back to [FixedProgression] for anything unreadable — a null column,
  /// malformed JSON, or a rule type written by a newer client.
  ///
  /// Degrading to "targets stay where the plan put them" is the safe failure:
  /// the user sees the prescription they were given rather than a screen that
  /// won't build, and nothing is written back, so the unknown rule survives
  /// for the version that understands it.
  static ProgressionRule decode(String? raw) {
    if (raw == null || raw.isEmpty) return const ProgressionRule.fixed();

    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return const ProgressionRule.fixed();

      return switch (json[_type]) {
        'linearWeekly' => ProgressionRule.linearWeekly(
          incrementKg: _double(json['incrementKg']) ?? 0,
          ceilingKg: _double(json['ceilingKg']),
        ),
        'doubleProgression' => ProgressionRule.doubleProgression(
          repsMin: _int(json['repsMin']) ?? 0,
          repsMax: _int(json['repsMax']) ?? 0,
          incrementKg: _double(json['incrementKg']) ?? 0,
        ),
        'topSetBackoff' => ProgressionRule.topSetBackoff(
          backoffSets: _int(json['backoffSets']) ?? 0,
          backoffPercent: _double(json['backoffPercent']) ?? 0,
        ),
        _ => const ProgressionRule.fixed(),
      };
    } on FormatException catch (error) {
      AppLogger.w('Malformed progression rule: $error', tag: 'DB');
      return const ProgressionRule.fixed();
    }
  }

  /// JSON numbers arrive as `int` or `double` depending on how they were
  /// written; a bare `as double` throws on `2` where `2.0` was meant.
  static double? _double(Object? value) => switch (value) {
    final num number => number.toDouble(),
    _ => null,
  };

  static int? _int(Object? value) => switch (value) {
    final num number => number.toInt(),
    _ => null,
  };
}
