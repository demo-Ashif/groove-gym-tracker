import 'package:flutter/material.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/utils/extensions/context_extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../domain/entities/session_log.dart';
import '../../../../domain/enums/training_enums.dart';
import '../../../../shared/widgets/app_sheet.dart';
import '../../../../shared/widgets/stepper_field.dart';
import 'rpe_dots.dart';

/// What the set editor hands back. Null result means "leave the set alone".
typedef SetEditorResult = ({
  double? weightKg,
  int? reps,
  int? durationSec,
  double? rpe,
  SetSide side,
  bool clear,
});

/// The inline editor behind a long-press on a set chip (ADR §9.2).
///
/// Steppers and dots only — no keyboard. The whole design target is a full
/// session logged with zero keystrokes, and this is the screen where that is
/// won or lost.
///
/// **A time-based slot gets a different sheet, not a disabled one.** A bike or
/// a treadmill is prescribed in minutes; showing it a weight stepper and a rep
/// stepper invites data that means nothing and pollutes every tonnage number
/// downstream.
class SetEditorSheet extends StatefulWidget {
  const SetEditorSheet({
    super.key,
    required this.setIndex,
    required this.isUnilateral,
    required this.weightStepKg,
    this.isTimeBased = false,
    this.existing,
    this.prefillWeightKg,
    this.prefillReps,
    this.prefillDurationSec,
  });

  /// Minutes the picker offers for time-based work: 5 through 60, in fives.
  /// Nobody prescribes a 7-minute bike, and a one-minute stepper would be
  /// sixty taps to reach an hour.
  static const durationMinuteStep = 5;
  static const minDurationMinutes = 5;
  static const maxDurationMinutes = 60;

  final int setIndex;
  final bool isUnilateral;

  /// The load-type's plate increment — 2.5 kg for a barbell, 1 kg for
  /// dumbbells. Stepping by a number the gym doesn't stock is friction.
  final double weightStepKg;

  /// Measured by the clock rather than by reps — the slot prescribes a
  /// duration, so the sheet offers minutes and nothing else.
  final bool isTimeBased;

  final SetLog? existing;
  final double? prefillWeightKg;
  final int? prefillReps;
  final int? prefillDurationSec;

  @override
  State<SetEditorSheet> createState() => _SetEditorSheetState();
}

class _SetEditorSheetState extends State<SetEditorSheet> {
  /// Weight is held in steps rather than kilograms so the stepper can work in
  /// integers and still land on 62.5.
  late int _weightSteps = _toSteps(
    widget.existing?.weightKg ?? widget.prefillWeightKg ?? 0,
  );
  late int _reps = widget.existing?.reps ?? widget.prefillReps ?? 0;

  /// Snapped to the nearest offered interval and clamped, so a prescription
  /// written as 12 minutes opens on a value the stepper can actually reach.
  late int _durationMin = _snapMinutes(
    ((widget.existing?.durationSec ?? widget.prefillDurationSec ?? 0) / 60)
        .round(),
  );

  late double? _rpe = widget.existing?.rpe;
  late SetSide _side = widget.existing?.side ?? SetSide.both;

  int _toSteps(double kg) => (kg / widget.weightStepKg).round();
  double get _weightKg => _weightSteps * widget.weightStepKg;

  static int _snapMinutes(int minutes) {
    const step = SetEditorSheet.durationMinuteStep;
    final snapped = (minutes / step).round() * step;
    return snapped.clamp(
      SetEditorSheet.minDurationMinutes,
      SetEditorSheet.maxDurationMinutes,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final formatters = Formatters.of(context);

    return AppSheet(
      title: l10n.setEditTitle(widget.setIndex + 1),
      actionLabel: l10n.commonSave,
      onAction: () => Navigator.of(context).pop((
        // Time-based work carries no load or reps: writing them would put
        // fictional numbers into tonnage and e1RM charts.
        weightKg: widget.isTimeBased || _weightKg <= 0 ? null : _weightKg,
        reps: widget.isTimeBased || _reps <= 0 ? null : _reps,
        durationSec: widget.isTimeBased ? _durationMin * 60 : null,
        rpe: _rpe,
        side: _side,
        clear: false,
      )),
      secondary: widget.existing == null
          ? null
          : TextButton(
              onPressed: () => Navigator.of(context).pop((
                weightKg: null,
                reps: null,
                durationSec: null,
                rpe: null,
                side: SetSide.both,
                clear: true,
              )),
              style: TextButton.styleFrom(
                foregroundColor: context.colors.error,
              ),
              child: Text(l10n.setClear),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.isTimeBased)
            StepperField(
              label: l10n.setDurationLabel,
              value: _durationMin,
              min: SetEditorSheet.minDurationMinutes,
              max: SetEditorSheet.maxDurationMinutes,
              step: SetEditorSheet.durationMinuteStep,
              formatValue: l10n.slotDurationMinutes,
              onChanged: (value) => setState(() => _durationMin = value),
            )
          else ...[
            StepperField(
              label: l10n.setWeightLabel,
              value: _weightSteps,
              max: _toSteps(500),
              formatValue: (steps) => l10n.setWeightValue(
                formatters.decimal(
                  steps * widget.weightStepKg,
                  // Whole numbers shouldn't render as "60.0" on a chip that is
                  // read at a glance between sets.
                  fractionDigits: (steps * widget.weightStepKg) % 1 == 0
                      ? 0
                      : 1,
                ),
              ),
              onChanged: (value) => setState(() => _weightSteps = value),
            ),
            const SizedBox(height: AppSpacing.sm),
            StepperField(
              label: l10n.setRepsLabel,
              value: _reps,
              max: 100,
              onChanged: (value) => setState(() => _reps = value),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          RpeDots(
            value: _rpe,
            onChanged: (value) => setState(() => _rpe = value),
          ),
          if (widget.isUnilateral) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              l10n.setSideLabel,
              style: context.textStyles.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            SegmentedButton<SetSide>(
              segments: [
                ButtonSegment(
                  value: SetSide.both,
                  label: Text(l10n.setSideBoth),
                ),
                ButtonSegment(
                  value: SetSide.left,
                  label: Text(l10n.setSideLeft),
                ),
                ButtonSegment(
                  value: SetSide.right,
                  label: Text(l10n.setSideRight),
                ),
              ],
              selected: {_side},
              showSelectedIcon: false,
              onSelectionChanged: (selection) =>
                  setState(() => _side = selection.first),
            ),
          ],
        ],
      ),
    );
  }
}

/// Four reasons and an escape hatch (ADR §9.2). Reason capture is what makes
/// Insights honest — "did the plyo block coincide with knee complaints?" is
/// only answerable if the skip said why.
class SkipReasonSheet extends StatelessWidget {
  const SkipReasonSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    final reasons = <(SkipReason, String, IconData)>[
      (SkipReason.pain, l10n.skipPain, Icons.healing_rounded),
      (SkipReason.time, l10n.skipTime, Icons.schedule_rounded),
      (SkipReason.equipment, l10n.skipEquipment, Icons.fitness_center_rounded),
      (SkipReason.feltOff, l10n.skipFeltOff, Icons.cloud_off_rounded),
      (SkipReason.other, l10n.skipOther, Icons.more_horiz_rounded),
    ];

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          0,
          AppSpacing.gutter,
          AppSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(l10n.skipTitle, style: context.textStyles.titleLarge),
            ),
            const SizedBox(height: AppSpacing.md),
            for (final (reason, label, icon) in reasons)
              ListTile(
                leading: Icon(icon),
                title: Text(label),
                onTap: () => Navigator.of(context).pop(reason),
              ),
          ],
        ),
      ),
    );
  }
}
