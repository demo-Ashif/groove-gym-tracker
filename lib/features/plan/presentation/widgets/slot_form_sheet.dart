import 'package:flutter/material.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/utils/extensions/context_extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../domain/entities/plan.dart';
import '../../../../domain/enums/training_enums.dart';
import '../../../../domain/values/progression_rule.dart';
import '../../../../shared/widgets/app_sheet.dart';
import '../../../../shared/widgets/stepper_field.dart';
import 'plan_labels.dart';

typedef SlotFormResult = ({
  int targetSets,
  int? targetReps,
  int? targetDurationSec,
  double? targetLoadKg,
  int restSeconds,
  bool perSide,
  ProgressionRule progression,
});

/// How a slot is measured. A prescription is reps *or* time — never both, or
/// the logger has two fields to write and adherence has two denominators.
enum SlotMeasure { reps, time }

/// The prescription editor: sets, reps or time, planned load, rest, per-side,
/// progression.
///
/// Everything is a stepper or a chip. Typing a number into a form is the
/// failure mode this app exists to avoid (ADR §2.1 principle 2), and these are
/// the same controls the in-session logger will use.
class SlotFormSheet extends StatefulWidget {
  const SlotFormSheet({
    super.key,
    required this.exerciseName,
    this.loadType,
    this.slot,
    this.onRequestDelete,
  });

  /// Shown as the sheet's subject, so the user knows what they are prescribing
  /// without the exercise name being editable here.
  final String exerciseName;

  /// Decides whether the form opens on reps or on time, and how big a step the
  /// weight control takes. Null when the catalog row was purged — the form
  /// still opens, defaulting to reps.
  final LoadType? loadType;

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

  /// Weight is held as a count of steps rather than a double, so the stepper
  /// can't accumulate floating-point drift over thirty taps. Step 0 means
  /// "not prescribed", which is a legitimate answer.
  late final double _weightStep = widget.loadType?.defaultIncrementKg ?? 2.5;

  late int _sets = widget.slot?.targetSets ?? 3;
  late int _reps = widget.slot?.targetReps ?? 8;

  /// Minutes on screen, seconds in the database — nobody prescribes a bike in
  /// seconds, and the stepper would need sixty taps per minute if they did.
  late int _durationMin = ((widget.slot?.targetDurationSec ?? 600) / 60)
      .round()
      .clamp(1, 180);

  late int _weightSteps = ((widget.slot?.targetLoadKg ?? 0) / _weightStep)
      .round();

  /// Existing slot: whatever it was saved as. New slot: whatever the exercise
  /// implies — a treadmill opens on time, a squat opens on reps — and the
  /// toggle is there when the guess is wrong.
  late SlotMeasure _measure = switch (widget.slot) {
    final slot? => slot.isTimeBased ? SlotMeasure.time : SlotMeasure.reps,
    null => switch (widget.loadType) {
      LoadType.time || LoadType.distance => SlotMeasure.time,
      _ => SlotMeasure.reps,
    },
  };

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

  /// Double progression's own rep range. It belongs to the **rule**, not to
  /// the prescription: a slot prescribes one rep number, and picking this rule
  /// is what introduces a range to climb.
  late int _doubleRepsMin = switch (_progression) {
    DoubleProgression(:final repsMin) => repsMin,
    _ => 8,
  };
  late int _doubleRepsMax = switch (_progression) {
    DoubleProgression(:final repsMax) => repsMax,
    _ => 12,
  };

  late int _backoffSets = switch (_progression) {
    TopSetBackoffProgression(:final backoffSets) => backoffSets,
    _ => 3,
  };
  late double _backoffPercent = switch (_progression) {
    TopSetBackoffProgression(:final backoffPercent) => backoffPercent,
    _ => 0.85,
  };

  bool get _isTime => _measure == SlotMeasure.time;

  double get _weightKg => _weightSteps * _weightStep;

  void _selectRule(ProgressionRule rule) => setState(() => _progression = rule);

  void _selectMeasure(SlotMeasure measure) {
    setState(() {
      _measure = measure;
      // A load-progression rule on a bike interval is noise. Time-based work
      // falls back to fixed rather than carrying a rule that can't fire.
      if (measure == SlotMeasure.time) {
        _progression = const ProgressionRule.fixed();
      }
    });
  }

  /// Rebuilds the active rule from the current parameter values.
  ProgressionRule get _rule => switch (_progression) {
    FixedProgression() => const ProgressionRule.fixed(),
    LinearWeeklyProgression() => ProgressionRule.linearWeekly(
      incrementKg: _increment,
    ),
    DoubleProgression() => ProgressionRule.doubleProgression(
      repsMin: _doubleRepsMin,
      repsMax: _doubleRepsMax,
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
        targetReps: _isTime ? null : _reps,
        targetDurationSec: _isTime ? _durationMin * 60 : null,
        // Zero steps is "not prescribed", not "zero kilos".
        targetLoadKg: _weightSteps > 0 ? _weightKg : null,
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
          SegmentedButton<SlotMeasure>(
            segments: [
              ButtonSegment(
                value: SlotMeasure.reps,
                label: Text(l10n.slotMeasureReps),
                icon: const Icon(Icons.repeat_rounded),
              ),
              ButtonSegment(
                value: SlotMeasure.time,
                label: Text(l10n.slotMeasureTime),
                icon: const Icon(Icons.timer_outlined),
              ),
            ],
            selected: {_measure},
            showSelectedIcon: false,
            onSelectionChanged: (selection) => _selectMeasure(selection.first),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Reps and time occupy the same slot in the form, so switching
          // measure resizes rather than reflowing the whole sheet.
          AnimatedSize(
            duration: AppDurations.base,
            curve: AppMotion.standard,
            alignment: Alignment.topCenter,
            child: _isTime
                ? StepperField(
                    key: const ValueKey('duration'),
                    label: l10n.slotDurationLabel,
                    value: _durationMin,
                    min: 1,
                    max: 180,
                    formatValue: l10n.slotDurationMinutes,
                    onChanged: (value) => setState(() => _durationMin = value),
                  )
                : StepperField(
                    key: const ValueKey('reps'),
                    label: l10n.slotRepsLabel,
                    value: _reps,
                    min: 1,
                    max: 50,
                    onChanged: (value) => setState(() => _reps = value),
                  ),
          ),
          const SizedBox(height: AppSpacing.sm),
          StepperField(
            label: l10n.slotLoadLabel,
            value: _weightSteps,
            max: (300 / _weightStep).round(),
            helper: l10n.slotLoadHelper,
            formatValue: (steps) => steps == 0
                ? l10n.slotLoadUnset
                : l10n.slotLoadKg(
                    formatters.decimal(
                      steps * _weightStep,
                      fractionDigits: (steps * _weightStep) % 1 == 0 ? 0 : 1,
                    ),
                  ),
            onChanged: (value) => setState(() => _weightSteps = value),
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
          // Progression advances a load or a rep count; neither means anything
          // for a ten-minute bike. Hidden rather than disabled, because a
          // control that can never apply is clutter.
          AnimatedSize(
            duration: AppDurations.base,
            curve: AppMotion.standard,
            alignment: Alignment.topCenter,
            child: _isTime
                ? const SizedBox(width: double.infinity)
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
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
                              selected:
                                  _progression.runtimeType ==
                                  option.runtimeType,
                              onSelected: (_) => _selectRule(option),
                            ),
                        ],
                      ),
                      // Only the selected rule's parameters are on screen — a
                      // form that shows every option's fields at once is a
                      // form nobody reads.
                      AnimatedSize(
                        duration: AppDurations.base,
                        curve: AppMotion.standard,
                        alignment: Alignment.topCenter,
                        child: _ProgressionParameters(
                          rule: _progression,
                          increment: _increment,
                          repsMin: _doubleRepsMin,
                          repsMax: _doubleRepsMax,
                          backoffSets: _backoffSets,
                          backoffPercent: _backoffPercent,
                          increments: _increments,
                          backoffPercents: _backoffPercents,
                          formatDecimal: formatters.decimal,
                          formatPercent: formatters.percent,
                          onIncrement: (value) =>
                              setState(() => _increment = value),
                          onRepsRange: (min, max) => setState(() {
                            _doubleRepsMin = min;
                            _doubleRepsMax = max;
                          }),
                          onBackoffSets: (value) =>
                              setState(() => _backoffSets = value),
                          onBackoffPercent: (value) =>
                              setState(() => _backoffPercent = value),
                        ),
                      ),
                    ],
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
    required this.repsMin,
    required this.repsMax,
    required this.backoffSets,
    required this.backoffPercent,
    required this.increments,
    required this.backoffPercents,
    required this.formatDecimal,
    required this.formatPercent,
    required this.onIncrement,
    required this.onRepsRange,
    required this.onBackoffSets,
    required this.onBackoffPercent,
  });

  final ProgressionRule rule;
  final double increment;
  final int repsMin;
  final int repsMax;
  final int backoffSets;
  final double backoffPercent;
  final List<double> increments;
  final List<double> backoffPercents;
  final String Function(num value, {int fractionDigits}) formatDecimal;
  final String Function(double fraction, {int fractionDigits}) formatPercent;
  final ValueChanged<double> onIncrement;
  final void Function(int min, int max) onRepsRange;
  final ValueChanged<int> onBackoffSets;
  final ValueChanged<double> onBackoffPercent;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return switch (rule) {
      FixedProgression() => const SizedBox.shrink(),
      LinearWeeklyProgression() => Padding(
        padding: const EdgeInsets.only(top: AppSpacing.md),
        child: _IncrementChips(
          increment: increment,
          increments: increments,
          formatDecimal: formatDecimal,
          onIncrement: onIncrement,
        ),
      ),
      // The one place a rep range still exists: this rule *is* "climb from the
      // floor to the ceiling, then add load and reset".
      DoubleProgression() => Padding(
        padding: const EdgeInsets.only(top: AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            RangeStepperField(
              minLabel: l10n.progressionRepFloor,
              maxLabel: l10n.progressionRepCeiling,
              minValue: repsMin,
              maxValue: repsMax,
              upperBound: 50,
              onChanged: onRepsRange,
            ),
            const SizedBox(height: AppSpacing.sm),
            _IncrementChips(
              increment: increment,
              increments: increments,
              formatDecimal: formatDecimal,
              onIncrement: onIncrement,
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

class _IncrementChips extends StatelessWidget {
  const _IncrementChips({
    required this.increment,
    required this.increments,
    required this.formatDecimal,
    required this.onIncrement,
  });

  final double increment;
  final List<double> increments;
  final String Function(num value, {int fractionDigits}) formatDecimal;
  final ValueChanged<double> onIncrement;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Wrap(
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
    );
  }
}
