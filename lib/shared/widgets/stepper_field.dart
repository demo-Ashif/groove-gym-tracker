import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';
import '../../core/di/injector.dart';
import '../../core/haptics/app_haptics.dart';
import '../../core/utils/extensions/context_extensions.dart';

/// Label, minus, value, plus. The app's answer to "type a number" —
/// tap-first, type-last (ADR §2.1 principle 2).
///
/// Both buttons pass `null` at their limit, so a control that cannot go
/// further reads as disabled instead of silently ignoring the tap. The haptic
/// is throttled by [AppHaptics], which is what stops a held finger turning
/// into a rattle.
class StepperField extends StatelessWidget {
  const StepperField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 999,
    this.step = 1,
    this.formatValue,
    this.helper,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;
  final int step;

  /// Renders the value — for units ("90s") or locale-aware digits.
  final String Function(int value)? formatValue;

  final String? helper;

  void _change(int next) {
    getIt<AppHaptics>().selection();
    onChanged(next.clamp(min, max));
  }

  @override
  Widget build(BuildContext context) {
    final canDecrease = value > min;
    final canIncrease = value < max;

    return Semantics(
      slider: true,
      label: label,
      value: formatValue?.call(value) ?? '$value',
      child: ExcludeSemantics(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: context.textStyles.bodyLarge),
                  if (helper case final text?)
                    Text(
                      text,
                      style: context.textStyles.bodySmall?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            _StepButton(
              icon: Icons.remove_rounded,
              onPressed: canDecrease ? () => _change(value - step) : null,
            ),
            // Fixed width so the row doesn't jitter as the number changes
            // width — the reason every numeral in the app is tabular.
            SizedBox(
              width: 56,
              child: Text(
                formatValue?.call(value) ?? '$value',
                textAlign: TextAlign.center,
                style: context.textStyles.titleMedium,
              ),
            ),
            _StepButton(
              icon: Icons.add_rounded,
              onPressed: canIncrease ? () => _change(value + step) : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;

    return IconButton.filledTonal(
      onPressed: onPressed,
      icon: Icon(icon),
      iconSize: 20,
      style: IconButton.styleFrom(
        minimumSize: const Size.square(AppSizes.minTapTarget),
        backgroundColor: enabled
            ? context.colors.surfaceContainerHighest
            : context.colors.surfaceContainerHigh,
        foregroundColor: enabled
            ? context.colors.onSurface
            : context.colors.outline,
      ),
    );
  }
}

/// Two steppers bound as a range, keeping `min <= max` without the user having
/// to think about order: pushing one past the other drags it along.
class RangeStepperField extends StatelessWidget {
  const RangeStepperField({
    super.key,
    required this.minLabel,
    required this.maxLabel,
    required this.minValue,
    required this.maxValue,
    required this.onChanged,
    this.lowerBound = 1,
    this.upperBound = 100,
  });

  final String minLabel;
  final String maxLabel;
  final int minValue;
  final int maxValue;
  final void Function(int min, int max) onChanged;
  final int lowerBound;
  final int upperBound;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        StepperField(
          label: minLabel,
          value: minValue,
          min: lowerBound,
          max: upperBound,
          onChanged: (next) =>
              onChanged(next, next > maxValue ? next : maxValue),
        ),
        const SizedBox(height: AppSpacing.sm),
        StepperField(
          label: maxLabel,
          value: maxValue,
          min: lowerBound,
          max: upperBound,
          onChanged: (next) =>
              onChanged(next < minValue ? next : minValue, next),
        ),
      ],
    );
  }
}
