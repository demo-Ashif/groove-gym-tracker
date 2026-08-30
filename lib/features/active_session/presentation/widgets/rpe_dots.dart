import 'package:flutter/material.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/haptics/app_haptics.dart';
import '../../../../core/utils/extensions/context_extensions.dart';
import '../../../../core/utils/formatters.dart';

/// RPE as a row of dots, 5 through 10.
///
/// A slider would demand precision nobody has mid-set, and a keypad would
/// break the no-typing rule. Six targets, one tap, and tapping the selected
/// dot clears it — rating a set is optional and must stay undoable.
class RpeDots extends StatelessWidget {
  const RpeDots({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 5,
    this.max = 10,
  });

  final double? value;
  final ValueChanged<double?> onChanged;
  final int min;
  final int max;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final formatters = Formatters.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(l10n.setRpeLabel, style: context.textStyles.bodyLarge),
            const Spacer(),
            Text(
              value == null
                  ? l10n.setRpeNone
                  : formatters.decimal(value!, fractionDigits: 0),
              style: context.textStyles.labelLarge?.copyWith(
                color: value == null
                    ? context.colors.onSurfaceVariant
                    : context.colors.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            for (var rpe = min; rpe <= max; rpe++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: _Dot(
                    label: formatters.integer(rpe),
                    selected: value != null && value! >= rpe,
                    onTap: () {
                      getIt<AppHaptics>().selection();
                      // Tapping the current value clears it.
                      onChanged(
                        value == rpe.toDouble() ? null : rpe.toDouble(),
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: AppRadius.fullAll,
            child: AnimatedContainer(
              duration: AppDurations.micro,
              curve: AppMotion.micro,
              height: AppSizes.minTapTarget,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? context.colors.primary
                    : context.colors.surfaceContainerHigh,
                borderRadius: AppRadius.fullAll,
              ),
              child: Text(
                label,
                style: context.textStyles.labelMedium?.copyWith(
                  color: selected
                      ? context.colors.onPrimary
                      : context.colors.onSurfaceVariant,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Energy as five faces (ADR §9.3).
class EnergyFaces extends StatelessWidget {
  const EnergyFaces({super.key, required this.value, required this.onChanged});

  final int? value;
  final ValueChanged<int?> onChanged;

  static const _faces = [
    Icons.sentiment_very_dissatisfied_rounded,
    Icons.sentiment_dissatisfied_rounded,
    Icons.sentiment_neutral_rounded,
    Icons.sentiment_satisfied_rounded,
    Icons.sentiment_very_satisfied_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var index = 0; index < _faces.length; index++)
          Expanded(
            child: IconButton(
              onPressed: () {
                getIt<AppHaptics>().selection();
                onChanged(value == index + 1 ? null : index + 1);
              },
              icon: Icon(_faces[index]),
              iconSize: 28,
              color: value == index + 1
                  ? context.colors.primary
                  : context.colors.outline,
              tooltip: '${index + 1}',
            ),
          ),
      ],
    );
  }
}
