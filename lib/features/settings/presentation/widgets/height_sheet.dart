import 'package:flutter/material.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/utils/extensions/context_extensions.dart';
import '../../../../domain/values/body_metrics.dart';
import '../../../../shared/widgets/app_sheet.dart';
import '../../../../shared/widgets/stepper_field.dart';

/// Enters a height, in whichever units are selected.
///
/// Pops the value in **centimetres** regardless of the units on screen, or a
/// negative to mean "clear it" — null already means the sheet was dismissed.
class HeightSheet extends StatefulWidget {
  const HeightSheet({super.key, required this.unitSystem, this.initialCm});

  final UnitSystem unitSystem;
  final double? initialCm;

  @override
  State<HeightSheet> createState() => _HeightSheetState();
}

class _HeightSheetState extends State<HeightSheet> {
  /// 170 cm / 5'7" is a neutral opening guess for someone who hasn't said.
  static const _defaultCm = 170.0;

  late double _cm = widget.initialCm ?? _defaultCm;

  /// Imperial is edited as two independent steppers rather than a converted
  /// decimal, so nudging inches never silently rewrites the feet.
  late int _feet = BodyUnits.cmToFeetInches(_cm).feet;
  late int _inches = BodyUnits.cmToFeetInches(_cm).inches.round();

  void _setImperial({int? feet, int? inches}) {
    setState(() {
      _feet = feet ?? _feet;
      _inches = inches ?? _inches;
      // 12 inches is the next foot up, not a valid inches value.
      if (_inches >= 12) {
        _feet += 1;
        _inches = 0;
      } else if (_inches < 0) {
        _feet -= 1;
        _inches = 11;
      }
      _cm = BodyUnits.feetInchesToCm(feet: _feet, inches: _inches.toDouble());
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return AppSheet(
      title: l10n.profileHeightLabel,
      actionLabel: l10n.commonSave,
      onAction: () => Navigator.of(context).pop(_cm),
      secondary: widget.initialCm == null
          ? null
          : TextButton(
              onPressed: () => Navigator.of(context).pop(-1.0),
              child: Text(l10n.commonClear),
            ),
      child: widget.unitSystem.isMetric
          ? StepperField(
              label: l10n.unitsCentimetres,
              value: _cm.round(),
              min: 80,
              max: 250,
              onChanged: (value) => setState(() => _cm = value.toDouble()),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                StepperField(
                  label: l10n.unitsFeet,
                  value: _feet,
                  min: 2,
                  max: 8,
                  onChanged: (value) => _setImperial(feet: value),
                ),
                const SizedBox(height: AppSpacing.sm),
                StepperField(
                  label: l10n.unitsInches,
                  value: _inches,
                  // Out-of-range values roll into the feet above rather than
                  // clamping, so 5'11" + 1 is 6'0" and not 5'11" again.
                  min: -1,
                  max: 12,
                  onChanged: (value) => _setImperial(inches: value),
                ),
              ],
            ),
    );
  }
}
