import 'package:flutter/material.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/utils/extensions/context_extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../domain/values/body_metrics.dart';
import '../../../../shared/widgets/app_sheet.dart';
import '../../../../shared/widgets/stepper_field.dart';

/// Records a bodyweight. Pops **kilograms** whatever the units on screen.
///
/// Held as tenths internally so the stepper is integer-valued and cannot
/// accumulate floating-point drift over a long press.
class WeightSheet extends StatefulWidget {
  const WeightSheet({super.key, required this.unitSystem, this.initialKg});

  final UnitSystem unitSystem;

  /// The last recorded weight, so re-weighing starts from where you were
  /// rather than from an arbitrary default.
  final double? initialKg;

  @override
  State<WeightSheet> createState() => _WeightSheetState();
}

class _WeightSheetState extends State<WeightSheet> {
  static const _defaultKg = 75.0;

  late double _kg = widget.initialKg ?? _defaultKg;

  /// Metric: tenths of a kilo. Imperial: whole stone plus tenths of a pound,
  /// which is how a UK bathroom scale actually reads.
  late int _tenthsKg = (_kg * 10).round();
  late int _stone = BodyUnits.kgToStonePounds(_kg).stone;
  late int _tenthsPounds = (BodyUnits.kgToStonePounds(_kg).pounds * 10).round();

  void _setMetric(int tenths) {
    setState(() {
      _tenthsKg = tenths;
      _kg = tenths / 10;
    });
  }

  void _setImperial({int? stone, int? tenthsPounds}) {
    setState(() {
      _stone = stone ?? _stone;
      _tenthsPounds = tenthsPounds ?? _tenthsPounds;
      // 14 lb is the next stone, not a valid pounds value.
      if (_tenthsPounds >= 140) {
        _stone += 1;
        _tenthsPounds = 0;
      } else if (_tenthsPounds < 0) {
        _stone -= 1;
        _tenthsPounds = 139;
      }
      _kg = BodyUnits.stonePoundsToKg(
        stone: _stone,
        pounds: _tenthsPounds / 10,
      );
      _tenthsKg = (_kg * 10).round();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final formatters = Formatters.of(context);

    return AppSheet(
      title: l10n.profileWeightLabel,
      actionLabel: l10n.commonSave,
      onAction: () => Navigator.of(context).pop(_kg),
      child: widget.unitSystem.isMetric
          ? StepperField(
              label: l10n.unitsKilograms,
              value: _tenthsKg,
              min: 200,
              max: 3000,
              // Half-kilo steps: finer than a bathroom scale resolves, and
              // coarse enough that a real change is a few taps.
              step: 5,
              formatValue: (tenths) =>
                  formatters.decimal(tenths / 10, fractionDigits: 1),
              onChanged: _setMetric,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                StepperField(
                  label: l10n.unitsStone,
                  value: _stone,
                  min: 3,
                  max: 45,
                  onChanged: (value) => _setImperial(stone: value),
                ),
                const SizedBox(height: AppSpacing.sm),
                StepperField(
                  label: l10n.unitsPounds,
                  value: _tenthsPounds,
                  // Rolls into the stone above rather than clamping.
                  min: -10,
                  max: 140,
                  step: 5,
                  formatValue: (tenths) =>
                      formatters.decimal(tenths / 10, fractionDigits: 1),
                  onChanged: (value) => _setImperial(tenthsPounds: value),
                ),
              ],
            ),
    );
  }
}
