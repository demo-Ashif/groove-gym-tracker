import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/app_routes.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../core/utils/extensions/context_extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../domain/entities/insights.dart';
import '../../../../domain/enums/training_enums.dart';
import '../../../../features/plan/presentation/widgets/plan_labels.dart';
import '../../../../shared/widgets/app_card.dart';
import 'adherence_ring.dart';
import 'card_empty_state.dart';

/// Adherence: what the window asked for against what actually happened
/// (ADR §11.2 card 1). The number the app exists to produce.
class AdherenceCard extends StatelessWidget {
  const AdherenceCard({
    super.key,
    required this.adherence,
    required this.skips,
  });

  final AdherenceStats adherence;
  final SkipBreakdown skips;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final formatters = Formatters.of(context);

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.insightsAdherenceTitle, style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          // 220ms cross-fade rather than a snap: switching range swaps this
          // between a ring and an empty state, and a hard cut reads as a bug.
          AnimatedSize(
            duration: AppDurations.base,
            curve: AppMotion.standard,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: AppDurations.base,
              switchInCurve: AppMotion.standard,
              child: adherence.hasData
                  ? _Summary(
                      key: const ValueKey('summary'),
                      stats: adherence,
                      skips: skips,
                    )
                  : CardEmptyState(
                      key: const ValueKey('empty'),
                      icon: Icons.donut_large_rounded,
                      title: l10n.insightsAdherenceEmptyTitle,
                      message: l10n.insightsAdherenceEmptyBody,
                      actionLabel: l10n.insightsAdherenceOpenPlan,
                      onAction: () => context.go(AppRoutes.plan),
                    ),
            ),
          ),
          if (!skips.isEmpty && adherence.hasData) ...[
            const SizedBox(height: AppSpacing.md),
            _SkipBreakdownRow(skips: skips, formatters: formatters),
          ],
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({super.key, required this.stats, required this.skips});

  final AdherenceStats stats;
  final SkipBreakdown skips;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final formatters = Formatters.of(context);
    final adherence = stats.adherence;

    final percentLabel = adherence == null
        ? '—'
        : formatters.percent(adherence);

    return Semantics(
      container: true,
      label: l10n.insightsAdherenceSemantics(
        adherence == null
            ? l10n.insightsAdherenceUnplanned
            : formatters.percent(adherence),
        formatters.integer(stats.completedSets),
        formatters.integer(stats.plannedSets),
      ),
      child: ExcludeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            AdherenceRing(
              value: adherence,
              label: percentLabel,
              caption: adherence == null
                  ? l10n.insightsAdherenceUnplanned
                  : l10n.insightsAdherenceTitle,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _StatLine(
                    icon: Icons.check_circle_outline_rounded,
                    text: l10n.insightsAdherenceSets(
                      formatters.integer(stats.completedSets),
                      formatters.integer(stats.plannedSets),
                    ),
                    color: theme.colorScheme.onSurface,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  _StatLine(
                    icon: Icons.event_available_rounded,
                    text: l10n.insightsAdherenceSessions(
                      formatters.integer(stats.completedSessions),
                      formatters.integer(stats.plannedSessions),
                    ),
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  if (skips.total > 0) ...[
                    const SizedBox(height: AppSpacing.xs),
                    _StatLine(
                      icon: Icons.remove_circle_outline_rounded,
                      text: l10n.insightsSkipsTitle,
                      trailing: formatters.integer(skips.total),
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatLine extends StatelessWidget {
  const _StatLine({
    required this.icon,
    required this.text,
    required this.color,
    this.trailing,
  });

  final IconData icon;
  final String text;
  final Color color;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (trailing case final value?)
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }
}

/// Skips by reason, pain first and in its own colour.
///
/// A light week caused by pain is a different fact from one caused by a short
/// lunch break, and the ADR is explicit that the two must not be one grey bar
/// (ADR §11.2).
class _SkipBreakdownRow extends StatelessWidget {
  const _SkipBreakdownRow({required this.skips, required this.formatters});

  final SkipBreakdown skips;
  final Formatters formatters;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.insightsSkipsTitle.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final entry in skips.ranked)
              _SkipChip(
                label: entry.key.label(l10n),
                count: formatters.integer(entry.value),
                isPain: entry.key == SkipReason.pain,
                painColor: theme.colorScheme.error,
              ),
          ],
        ),
      ],
    );
  }
}

class _SkipChip extends StatelessWidget {
  const _SkipChip({
    required this.label,
    required this.count,
    required this.isPain,
    required this.painColor,
  });

  final String label;
  final String count;
  final bool isPain;
  final Color painColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final foreground = isPain ? painColor : scheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: AppRadius.smAll,
        border: isPain
            ? Border.all(color: painColor.withValues(alpha: 0.4))
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(color: foreground),
          ),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            count,
            style: theme.textTheme.labelMedium?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
