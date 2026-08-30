import 'package:flutter/material.dart';

import '../../core/utils/extensions/context_extensions.dart';
import '../../core/utils/formatters.dart';
import '../../domain/values/body_metrics.dart';

/// Body measurements rendered in the user's units.
///
/// Storage is always metric and conversion happens here, at the edge — the
/// same rule [UnitSystem] states. Shared rather than feature-local because
/// Profile records these numbers and Insights charts them, and two
/// implementations would eventually disagree about rounding.

/// `178 cm`, or `5′ 10″`.
String formatHeight(
  BuildContext context, {
  required double cm,
  required UnitSystem unitSystem,
}) {
  final l10n = context.l10n;
  final formatters = Formatters.of(context);

  if (unitSystem.isMetric) {
    return l10n.unitsCm(formatters.decimal(cm, fractionDigits: 0));
  }

  final imperial = BodyUnits.cmToFeetInches(cm);
  return l10n.unitsFeetInches(
    formatters.integer(imperial.feet),
    formatters.decimal(imperial.inches, fractionDigits: 0),
  );
}

/// `82.5 kg`, or `12 st 13.9 lb`.
String formatWeight(
  BuildContext context, {
  required double kg,
  required UnitSystem unitSystem,
}) {
  final l10n = context.l10n;
  final formatters = Formatters.of(context);

  if (unitSystem.isMetric) {
    return l10n.unitsKg(formatters.decimal(kg, fractionDigits: 1));
  }

  final imperial = BodyUnits.kgToStonePounds(kg);
  return l10n.unitsStonePounds(
    formatters.integer(imperial.stone),
    formatters.decimal(imperial.pounds, fractionDigits: 1),
  );
}
