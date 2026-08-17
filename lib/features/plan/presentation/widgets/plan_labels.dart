import '../../../../domain/enums/training_enums.dart';
import '../../../../domain/values/progression_rule.dart';
import '../../../../l10n/generated/app_localizations.dart';

/// Enum → display text, in one place.
///
/// Exhaustive switches with no `default`: adding a block kind or a progression
/// rule stops compiling here until it has a string, which is the point. A map
/// lookup would return null in front of a user instead.
extension BlockKindLabel on BlockKind {
  String label(L10n l10n) => switch (this) {
    BlockKind.warmup => l10n.blockKindWarmup,
    BlockKind.main => l10n.blockKindMain,
    BlockKind.core => l10n.blockKindCore,
    BlockKind.conditioning => l10n.blockKindConditioning,
    BlockKind.cooldown => l10n.blockKindCooldown,
    BlockKind.plyo => l10n.blockKindPlyo,
  };
}

extension MovementPatternLabel on MovementPattern {
  String label(L10n l10n) => switch (this) {
    MovementPattern.hinge => l10n.patternHinge,
    MovementPattern.squat => l10n.patternSquat,
    MovementPattern.push => l10n.patternPush,
    MovementPattern.pull => l10n.patternPull,
    MovementPattern.carry => l10n.patternCarry,
    MovementPattern.rotation => l10n.patternRotation,
    MovementPattern.core => l10n.patternCore,
    MovementPattern.plyo => l10n.patternPlyo,
    MovementPattern.conditioning => l10n.patternConditioning,
    MovementPattern.mobility => l10n.patternMobility,
  };
}

extension SkipReasonLabel on SkipReason {
  String label(L10n l10n) => switch (this) {
    SkipReason.pain => l10n.skipPain,
    SkipReason.time => l10n.skipTime,
    SkipReason.equipment => l10n.skipEquipment,
    SkipReason.feltOff => l10n.skipFeltOff,
    SkipReason.other => l10n.skipOther,
  };
}

extension BodySectionLabel on BodySection {
  String label(L10n l10n) => switch (this) {
    BodySection.chest => l10n.sectionChest,
    BodySection.upperBack => l10n.sectionUpperBack,
    BodySection.lowerBack => l10n.sectionLowerBack,
    BodySection.shoulders => l10n.sectionShoulders,
    BodySection.arms => l10n.sectionArms,
    BodySection.core => l10n.sectionCore,
    BodySection.glutes => l10n.sectionGlutes,
    BodySection.legs => l10n.sectionLegs,
    BodySection.fullBody => l10n.sectionFullBody,
    BodySection.cardio => l10n.sectionCardio,
    BodySection.mobility => l10n.sectionMobility,
  };
}

extension ProgressionRuleLabel on ProgressionRule {
  /// Short name, for a selector.
  String label(L10n l10n) => switch (this) {
    FixedProgression() => l10n.progressionFixed,
    LinearWeeklyProgression() => l10n.progressionLinearWeekly,
    DoubleProgression() => l10n.progressionDouble,
    TopSetBackoffProgression() => l10n.progressionTopSetBackoff,
  };

  /// The rule spelled out, for a summary row. Null for the default, which is
  /// worth no words at all.
  ///
  /// Numbers are formatted by the caller's [formatDecimal] so they render in
  /// the active locale's digits and separator (ADR §12.2 rule 5).
  String? detail(
    L10n l10n, {
    required String Function(num value) formatDecimal,
    required String Function(double fraction) formatPercent,
  }) => switch (this) {
    FixedProgression() => null,
    LinearWeeklyProgression(:final incrementKg) =>
      l10n.progressionLinearWeeklyDetail(formatDecimal(incrementKg)),
    DoubleProgression(:final repsMin, :final repsMax, :final incrementKg) =>
      l10n.progressionDoubleDetail(
        repsMin,
        repsMax,
        formatDecimal(incrementKg),
      ),
    TopSetBackoffProgression(:final backoffSets, :final backoffPercent) =>
      l10n.progressionTopSetBackoffDetail(
        backoffSets,
        formatPercent(backoffPercent),
      ),
  };
}
