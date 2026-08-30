import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/app_routes.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../core/utils/extensions/context_extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../domain/entities/insights.dart';
import '../../../../domain/services/trend_service.dart';
import '../../../../domain/values/body_metrics.dart';
import '../../../../domain/values/calendar_date.dart';
import '../../../../shared/l10n/body_format.dart';
import '../../../../shared/widgets/app_card.dart';
import 'card_empty_state.dart';
import 'weight_trend_chart.dart';

/// Body weight over the window: the raw weigh-ins, the line through them, and
/// how far it moved (ADR §11.2 card 2).
class WeightTrendCard extends StatelessWidget {
  const WeightTrendCard({
    super.key,
    required this.points,
    required this.unitSystem,
    this.phaseBoundaries = const [],
    this.movingAverageDays = 7,
  });

  final List<WeightPoint> points;
  final UnitSystem unitSystem;
  final List<CalendarDate> phaseBoundaries;
  final int movingAverageDays;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final formatters = Formatters.of(context);

    final latest = points.isEmpty ? null : points.last;
    final change = TrendService.change(points);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  l10n.insightsWeightTitle,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              if (latest case final point?)
                Text(
                  formatWeight(context, kg: point.kg, unitSystem: unitSystem),
                  style: theme.textTheme.titleLarge,
                ),
            ],
          ),
          if (change != null && change.abs() >= 0.05) ...[
            const SizedBox(height: AppSpacing.xxs),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Text(
                l10n.insightsWeightDelta(
                  _formatDelta(context, change, formatters),
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          AnimatedSize(
            duration: AppDurations.base,
            curve: AppMotion.standard,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: AppDurations.base,
              switchInCurve: AppMotion.standard,
              child: points.length < 2
                  ? CardEmptyState(
                      key: const ValueKey('empty'),
                      icon: Icons.show_chart_rounded,
                      title: l10n.insightsWeightEmptyTitle,
                      message: l10n.insightsWeightEmptyBody,
                      actionLabel: l10n.insightsWeightGoToProfile,
                      onAction: () => context.go(AppRoutes.profile),
                    )
                  : _Chart(
                      // Keyed on the window's own points so a range change
                      // swaps charts rather than morphing one into the other.
                      key: ValueKey(points.length),
                      points: points,
                      unitSystem: unitSystem,
                      phaseBoundaries: phaseBoundaries,
                    ),
            ),
          ),
          if (points.length >= 2) ...[
            const SizedBox(height: AppSpacing.sm),
            _Legend(movingAverageDays: movingAverageDays),
          ],
        ],
      ),
    );
  }

  /// A change, signed, in the unit the user reads.
  ///
  /// Imperial deltas are pounds rather than stone-and-pounds: a week never
  /// moves a whole stone, and "0 st 2.0 lb" is a worse way to say "2 lb".
  String _formatDelta(
    BuildContext context,
    double kg,
    Formatters formatters,
  ) {
    final l10n = context.l10n;
    final sign = kg > 0 ? '+' : '−';
    final magnitude = kg.abs();

    final value = unitSystem.isMetric
        ? l10n.unitsKg(formatters.decimal(magnitude, fractionDigits: 1))
        : l10n.unitsLb(
            formatters.decimal(
              BodyUnits.kgToPounds(magnitude),
              fractionDigits: 1,
            ),
          );

    return '$sign$value';
  }
}

class _Chart extends StatelessWidget {
  const _Chart({
    super.key,
    required this.points,
    required this.unitSystem,
    required this.phaseBoundaries,
  });

  final List<WeightPoint> points;
  final UnitSystem unitSystem;
  final List<CalendarDate> phaseBoundaries;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final formatters = Formatters.of(context);

    return Semantics(
      // The chart is a drawing; without this a screen reader finds nothing
      // here at all.
      label: l10n.insightsWeightSemantics(
        formatters.integer(points.length),
        formatWeight(context, kg: points.last.kg, unitSystem: unitSystem),
      ),
      child: ExcludeSemantics(
        child: WeightTrendChart(
          points: points,
          phaseBoundaries: phaseBoundaries,
          formatWeight: (kg) =>
              formatWeight(context, kg: kg, unitSystem: unitSystem),
          formatDate: (date) => formatters.dayAndMonth(date.toDateTime()),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.movingAverageDays});

  final int movingAverageDays;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final formatters = Formatters.of(context);

    return Row(
      children: [
        _LegendSwatch(
          color: theme.colorScheme.primary,
          isLine: true,
          label: l10n.insightsWeightAverage(
            formatters.integer(movingAverageDays),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        _LegendSwatch(
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
          isLine: false,
          label: l10n.insightsWeightRaw,
        ),
      ],
    );
  }
}

class _LegendSwatch extends StatelessWidget {
  const _LegendSwatch({
    required this.color,
    required this.isLine,
    required this.label,
  });

  final Color color;
  final bool isLine;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: isLine ? 16 : 6,
          height: isLine ? 2.5 : 6,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(isLine ? 2 : 3),
          ),
        ),
        const SizedBox(width: AppSpacing.xxs),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
