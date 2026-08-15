import 'package:equatable/equatable.dart';

import '../enums/training_enums.dart';

/// A catalog exercise (ADR §4.3).
///
/// Pure: no drift, no JSON, no Flutter. The data layer maps the row onto this
/// and back, which is what lets a cubit be tested against a fake repository
/// with no database in sight.
///
/// **Naming is a union of two cases**, and the type enforces which one:
/// a seeded exercise carries [nameKey] and localizes through ARB; a
/// user-created one carries [customName] and is never translated (ADR §12.4).
class Exercise extends Equatable {
  const Exercise({
    required this.id,
    required this.pattern,
    required this.loadType,
    this.nameKey,
    this.customName,
    this.aliases = const [],
    this.isUnilateral = false,
    this.primaryMuscles = const [],
    this.isSystem = false,
    this.isHidden = false,
  }) : assert(
         (nameKey == null) != (customName == null),
         'An exercise has exactly one name source: an ARB key (system) or '
         'literal text (user-created).',
       );

  final String id;

  /// ARB key, e.g. `exRomanianDeadlift`. Resolve with `exerciseDisplayName`;
  /// never render this directly.
  final String? nameKey;

  /// Literal, in the user's own language.
  final String? customName;

  /// Alternate spellings the plan parser matches against.
  final List<String> aliases;

  final MovementPattern pattern;
  final LoadType loadType;
  final bool isUnilateral;

  /// Stable muscle identifiers, not display text.
  final List<String> primaryMuscles;

  /// Seeded. May be hidden but not edited — one device's rename would
  /// otherwise rewrite the label on everyone's history.
  final bool isSystem;

  /// Soft-deleted: excluded from pickers, still resolvable by every set log
  /// that points at it.
  final bool isHidden;

  bool get isEditable => !isSystem;

  /// Whether an e1RM can honestly be computed from sets of this exercise
  /// (ADR §4.4).
  bool get supportsE1rm => loadType.isLoadable;

  @override
  List<Object?> get props => [
    id,
    nameKey,
    customName,
    aliases,
    pattern,
    loadType,
    isUnilateral,
    primaryMuscles,
    isSystem,
    isHidden,
  ];
}
