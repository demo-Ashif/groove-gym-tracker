import 'package:flutter/material.dart';

import '../../../../core/utils/extensions/context_extensions.dart';
import '../../../../domain/values/body_metrics.dart';
import '../../../../l10n/generated/app_localizations.dart';

extension GenderLabel on Gender {
  String label(L10n l10n) => switch (this) {
    Gender.female => l10n.genderFemale,
    Gender.male => l10n.genderMale,
    Gender.other => l10n.genderOther,
    Gender.unspecified => l10n.genderUnspecified,
  };
}

extension BmiBandLabel on BmiBand {
  String label(L10n l10n) => switch (this) {
    BmiBand.underweight => l10n.bmiUnderweight,
    BmiBand.healthy => l10n.bmiHealthy,
    BmiBand.overweight => l10n.bmiOverweight,
    BmiBand.obese => l10n.bmiObese,
  };

  /// Healthy reads as success; everything else is a neutral note rather than
  /// an alarm. BMI is a population statistic with well-known limits on a
  /// lifter, and painting "obese" in error red would be the app editorialising
  /// about a body it cannot actually measure.
  Color containerColor(BuildContext context) => switch (this) {
    BmiBand.healthy => context.semanticColors.successContainer,
    _ => context.colors.surfaceContainerHighest,
  };

  Color onContainerColor(BuildContext context) => switch (this) {
    BmiBand.healthy => context.semanticColors.onSuccessContainer,
    _ => context.colors.onSurfaceVariant,
  };
}
