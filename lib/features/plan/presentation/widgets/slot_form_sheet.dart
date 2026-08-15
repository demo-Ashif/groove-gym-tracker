import 'package:flutter/material.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/utils/extensions/context_extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../domain/entities/plan.dart';
import '../../../../domain/values/progression_rule.dart';
import '../../../../shared/widgets/app_sheet.dart';
import '../../../../shared/widgets/stepper_field.dart';
import 'plan_labels.dart';

typedef SlotFormResult = ({
  int targetSets,
  int targetRepsMin,
  int targetRepsMax,
  int restSeconds,
  bool perSide,
  ProgressionRule progression,
});

/// The prescription editor: sets, reps, rest, per-side, progression.
///
/// Everything is a stepper or a chip. Typing a number into a form is the
/// failure mode this app exists to avoid (ADR §2.1 principle 2), and these are
/// the same controls the in-session logger will use.
class SlotFormSheet extends StatefulWidget {
  const SlotFormSheet({
    super.key,
    required this.exerciseName,
    this.slot,
    this.onRequestDelete,
  });

  /// Shown as the sheet's subject, so the user knows what they are prescribing
  /// without the exercise name being editable here.
  final String exerciseName;

  final ExerciseTemplate? slot;

  /// Removal lives here rather than only on a long-press: a gesture nobody can
  /// see is a feature nobody has. Called after the sheet closes, so the
  /// confirmation dialog opens on the page rather than on a dying route.
  final VoidCallback? onRequestDelete;

  @override
  State<SlotFormSheet> createState() => _SlotFormSheetState();
}

class _SlotFormSheetState extends State<SlotFormSheet> {
  /// Increments a gym actually has plates for.
  static const _increments = [1.0, 2.5, 5.0];
  static const _backoffPercents = [0.7, 0.75, 0.8, 0.85, 0.9];

  late int _sets = widget.slot?.targetSets ?? 3;
  late int _repsMin = widget.slot?.targetRepsMin ?? 8;
  late int _repsMax =
      widget.slot?.targetRepsMax ?? widget.slot?.targetRepsMin ?? 8;
  late int _rest = widget.slot?.restSeconds ?? 90;
  late bool _perSide = widget.slot?.perSide ?? false;
  late ProgressionRule _progression =
      widget.slot?.progression ?? const ProgressionRule.fixed();

  /// Keeps the increment chips populated when switching between rules, so
  /// flipping from linear to double and back doesn't reset the number.
  late double _increment = switch (_progression) {
    LinearWeeklyProgression(:final incrementKg) => incrementKg,
    DoubleProgression(:final incrementKg) => incrementKg,
    _ => 2.5,
  };
  late int _backoffSets = switch (_progression) {
    TopSetBackoffProgression(:final backoffSets) => backoffSets,
    _ => 3,
  };
  late double _backoffPercent = switch (_progression) {
    TopSetBackoffProgression(:final backoffPercent) => backoffPercent,
    _ => 0.85,
  };

  void _selectRule(ProgressionRule rule) => setState(() => _progression = rule);

  /// Rebuilds the active rule from the current parameter values.
  ProgressionRule get _rule => switch (_progression) {
    FixedProgression() => const ProgressionRule.fixed(),
    LinearWeeklyProgression() => ProgressionRule.linearWeekly(
      incrementKg: _increment,
    ),
    DoubleProgression() => ProgressionRule.doubleProgression(
      repsMin: _repsMin,
      repsMax: _repsMax,
      incrementKg: _increment,
    ),
    TopSetBackoffProgression() => ProgressionRule.topSetBackoff(
      backoffSets: _backoffSets,
      backoffPercent: _backoffPercent,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final formatters = Formatters.of(context);

    return AppSheet(
      title: widget.exerciseName,
      actionLabel: widget.slot == null ? l10n.commonAdd : l10n.commonSave,
      secondary: widget.onRequestDelete == null
          ? null
          : TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                widget.onRequestDelete!();
              },
              style: TextButton.styleFrom(
                foregroundColor: context.colors.error,
              ),
              child: Text(l10n.commonDelete),
            ),
      onAction: () => Navigator.of(context).pop((
        targetSets: _sets,
        targetRepsMin: _repsMin,
        targetRepsMax: _repsMax,
        restSeconds: _rest,
        perSide: _perSide,
        progression: _rule,
      )),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StepperField(
            label: l10n.slotSetsLabel,
            value: _sets,
            min: 1,
            max: 12,
            onChanged: (value) => setState(() => _sets = value),
          ),
          const SizedBox(height: AppSpacing.sm),
          RangeStepperField(
            minLabel: l10n.slotRepsLabel,
            maxLabel: l10n.slotRepsRangeLabel,
            minValue: _repsMin,
            maxValue: _repsMax,
            upperBound: 50,
            onChanged: (min, max) => setState(() {
              _repsMin = min;
              _repsMax = max;
            }),
          ),
          const SizedBox(height: AppSpacing.sm),
          StepperField(
            label: l10n.slotRestLabel,
            value: _rest,
            max: 600,
            step: 15,
            formatValue: (value) => l10n.slotRestSeconds(value),
            onChanged: (value) => setState(() => _rest = value),
          ),
          const SizedBox(height: AppSpacing.xs),
          SwitchListTile.adaptive(
            value: _perSide,
            onChanged: (value) => setState(() => _perSide = value),
            title: Text(l10n.slotPerSideLabel),
            subtitle: Text(l10n.slotPerSideDescription),
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.slotProgressionLabel,
            style: context.textStyles.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final option in const [
                ProgressionRule.fixed(),
                ProgressionRule.linearWeekly(incrementKg: 2.5),
                ProgressionRule.doubleProgression(
                  repsMin: 8,
                  repsMax: 12,
                  incrementKg: 2.5,
                ),
                ProgressionRule.topSetBackoff(
                  backoffSets: 3,
                  backoffPercent: 0.85,
                ),
              ])
                ChoiceChip(
                  label: Text(option.label(l10n)),
                  selected: _progression.runtimeType == option.runtimeType,
                  onSelected: (_) => _selectRule(option),
                ),
            ],
          ),
          // Only the selected rule's parameters are on screen — a form that
          // shows every option's fields at once is a form nobody reads.
          AnimatedSize(
            duration: AppDurations.base,
            curve: AppMotion.standard,
            alignment: Alignment.topCenter,
            child: _ProgressionParameters(
              rule: _progression,
              increment: _increment,
              backoffSets: _backoffSets,
              backoffPercent: _backoffPercent,
              increments: _increments,
              backoffPercents: _backoffPercents,
              formatDecimal: formatters.decimal,
              formatPercent: formatters.percent,
              onIncrement: (value) => setState(() => _increment = value),
              onBackoffSets: (value) => setState(() => _backoffSets = value),
              onBackoffPercent: (value) =>
                  setState(() => _backoffPercent = value),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressionParameters extends StatelessWidget {
  const _ProgressionParameters({
    required this.rule,
    required this.increment,
    required this.backoffSets,
    required this.backoffPercent,
    required this.increments,
    required this.backoffPercents,
    required this.formatDecimal,
    required this.formatPercent,
    required this.onIncrement,
    required this.onBackoffSets,
    required this.onBackoffPercent,
  });

  final ProgressionRule rule;
  final double increment;
  final int backoffSets;
  final double backoffPercent;
  final List<double> increments;
  final List<double> backoffPercents;
  final String Function(num value, {int fractionDigits}) formatDecimal;
  final String Function(double fraction, {int fractionDigits}) formatPercent;
  final ValueChanged<double> onIncrement;
  final ValueChanged<int> onBackoffSets;
  final ValueChanged<double> onBackoffPercent;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return switch (rule) {
      FixedProgression() => const SizedBox.shrink(),
      LinearWeeklyProgression() || DoubleProgression() => Padding(
        padding: const EdgeInsets.only(top: AppSpacing.md),
        child: Wrap(
          spacing: AppSpacing.xs,
          children: [
            for (final value in increments)
              ChoiceChip(
                label: Text(
                  l10n.progressionLinearWeeklyDetail(formatDecimal(value)),
                ),
                selected: increment == value,
                onSelected: (_) => onIncrement(value),
              ),
          ],
        ),
      ),
      TopSetBackoffProgression() => Padding(
        padding: const EdgeInsets.only(top: AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StepperField(
              label: l10n.progressionTopSetBackoff,
              value: backoffSets,
              min: 1,
              max: 6,
              onChanged: onBackoffSets,
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xs,
              children: [
                for (final value in backoffPercents)
                  ChoiceChip(
                    label: Text(formatPercent(value)),
                    selected: backoffPercent == value,
                    onSelected: (_) => onBackoffPercent(value),
                  ),
              ],
            ),
          ],
        ),
      ),
    };
  }
}
