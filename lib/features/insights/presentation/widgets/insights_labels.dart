import 'package:flutter/widgets.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../domain/values/insights_range.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../cubit/insights_range_cubit.dart';

/// Filter kind → chip text. Exhaustive with no `default`, so a new kind stops
/// compiling here until it has a string.
extension InsightsRangeKindLabel on InsightsRangeKind {
  String label(L10n l10n) => switch (this) {
    InsightsRangeKind.day => l10n.insightsRangeDay,
    InsightsRangeKind.week => l10n.insightsRangeWeek,
    InsightsRangeKind.month => l10n.insightsRangeMonth,
    InsightsRangeKind.cycle => l10n.insightsRangeCycle,
    InsightsRangeKind.all => l10n.insightsRangeAll,
  };
}

/// What the current window reads as under the filter — "Sun, 16 Aug",
/// "16 Aug – 22 Aug", "August 2026", "Cycle 1 · 16 Aug – 26 Sep".
///
/// Dates go through `intl` rather than being assembled from parts: the order
/// of day and month is locale data (ADR §12.2).
String insightsRangeLabel(
  BuildContext context, {
  required InsightsRangeState state,
}) {
  final l10n = L10n.of(context);
  final formatters = Formatters.of(context);
  final range = state.range;

  String span() {
    final from = range.start;
    final to = range.end;
    if (from == null || to == null) return l10n.insightsRangeAllLabel;
    return l10n.insightsRangeSpan(
      formatters.dayAndMonth(from.toDateTime()),
      formatters.dayAndMonth(to.toDateTime()),
    );
  }

  return switch (state.kind) {
    InsightsRangeKind.day => formatters.mediumDate(state.anchor.toDateTime()),
    InsightsRangeKind.week => span(),
    InsightsRangeKind.month => formatters.monthAndYear(
      state.anchor.toDateTime(),
    ),
    // The phase's own name is the point of the Cycle filter — "Cycle 1 —
    // Foundation" says more than the dates it happens to cover.
    InsightsRangeKind.cycle => switch (state.phase) {
      final phase? => '${phase.name} · ${span()}',
      null => span(),
    },
    InsightsRangeKind.all => l10n.insightsRangeAllLabel,
  };
}
