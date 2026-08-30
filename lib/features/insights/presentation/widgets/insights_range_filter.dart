import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/utils/extensions/context_extensions.dart';
import '../cubit/insights_range_cubit.dart';
import 'insights_labels.dart';

/// The persistent global filter: Day · Week · Month · Cycle · All, plus the
/// window it currently resolves to (ADR §11.1).
///
/// Scrollable rather than a fixed [SegmentedButton]: five segments at 1.4×
/// text scale do not fit a 360dp phone, and an overflowing filter is a broken
/// screen for exactly the users who need the large type.
class InsightsRangeFilter extends StatelessWidget {
  const InsightsRangeFilter({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return BlocBuilder<InsightsRangeCubit, InsightsRangeState>(
      builder: (context, state) {
        final cubit = context.read<InsightsRangeCubit>();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              label: l10n.insightsRangeLabel,
              container: true,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final kind in state.availableKinds) ...[
                      _RangeChip(
                        label: kind.label(l10n),
                        selected: kind == state.kind,
                        onTap: () => cubit.selectKind(kind),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            _WindowRow(state: state),
          ],
        );
      },
    );
  }
}

class _RangeChip extends StatelessWidget {
  const _RangeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final background = selected
        ? scheme.primaryContainer
        : scheme.surfaceContainerHighest;
    final foreground = selected
        ? scheme.onPrimaryContainer
        : scheme.onSurfaceVariant;

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.fullAll,
          child: AnimatedContainer(
            duration: AppDurations.micro,
            curve: AppMotion.micro,
            constraints: const BoxConstraints(
              minHeight: AppSizes.minTapTarget,
              minWidth: 64,
            ),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: background,
              borderRadius: AppRadius.fullAll,
            ),
            child: AnimatedDefaultTextStyle(
              duration: AppDurations.micro,
              curve: AppMotion.micro,
              style: (theme.textTheme.labelLarge ?? const TextStyle()).copyWith(
                color: foreground,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
              child: Text(label),
            ),
          ),
        ),
      ),
    );
  }
}

/// The window under the chips, with its two arrows.
class _WindowRow extends StatelessWidget {
  const _WindowRow({required this.state});

  final InsightsRangeState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final cubit = context.read<InsightsRangeCubit>();
    final label = insightsRangeLabel(context, state: state);

    return Row(
      children: [
        IconButton(
          // Null rather than a disabled-looking callback: it reads as
          // unavailable to a screen reader too.
          onPressed: state.canGoBack ? cubit.previous : null,
          icon: const Icon(Icons.chevron_left_rounded),
          tooltip: l10n.insightsRangePrevious,
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: AppDurations.base,
            switchInCurve: AppMotion.standard,
            child: Text(
              label,
              // Distinct key, or the switcher cross-fades a widget with
              // itself and nothing appears to change.
              key: ValueKey(label),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        IconButton(
          onPressed: state.canGoForward ? cubit.next : null,
          icon: const Icon(Icons.chevron_right_rounded),
          tooltip: l10n.insightsRangeNext,
        ),
      ],
    );
  }
}
