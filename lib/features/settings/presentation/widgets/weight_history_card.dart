import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/utils/extensions/context_extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../domain/entities/check_in.dart';
import '../../../../domain/repositories/check_in_repository.dart';
import '../../../../domain/values/body_metrics.dart';
import '../../../../shared/l10n/body_format.dart';
import '../../../../shared/widgets/app_card.dart';
import '../cubit/preferences_cubit.dart';

/// The bodyweight trend — the last handful of entries with the change between
/// them, which is the only thing a single number can't tell you.
class WeightHistoryCard extends StatelessWidget {
  const WeightHistoryCard({super.key, this.maxEntries = 6});

  final int maxEntries;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final unitSystem = context
        .watch<PreferencesCubit>()
        .state
        .preferences
        .unitSystem;

    return StreamBuilder<List<CheckIn>>(
      stream: getIt<CheckInRepository>().watchCheckIns(limit: maxEntries),
      builder: (context, snapshot) {
        final entries = (snapshot.data ?? const <CheckIn>[])
            .where((entry) => entry.weightKg != null)
            .toList(growable: false);

        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.profileWeightHistoryTitle,
                style: context.textStyles.titleSmall,
              ),
              const SizedBox(height: AppSpacing.xs),
              if (entries.isEmpty)
                Text(
                  l10n.profileWeightHistoryEmpty,
                  style: context.textStyles.bodySmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                )
              else
                for (var index = 0; index < entries.length; index++)
                  _HistoryRow(
                    entry: entries[index],
                    // The list is newest-first, so the comparison point is the
                    // next element, not the previous one.
                    previous: index + 1 < entries.length
                        ? entries[index + 1]
                        : null,
                    unitSystem: unitSystem,
                  ),
            ],
          ),
        );
      },
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.entry,
    required this.previous,
    required this.unitSystem,
  });

  final CheckIn entry;
  final CheckIn? previous;
  final UnitSystem unitSystem;

  @override
  Widget build(BuildContext context) {
    final formatters = Formatters.of(context);
    final semantic = context.semanticColors;

    final weight = entry.weightKg!;
    final previousWeight = previous?.weightKg;
    final delta = previousWeight == null ? null : weight - previousWeight;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              formatters.mediumDate(entry.date.toDateTime()),
              style: context.textStyles.bodyMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            formatWeight(context, kg: weight, unitSystem: unitSystem),
            style: context.textStyles.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (delta != null && delta.abs() >= 0.05) ...[
            const SizedBox(width: AppSpacing.xs),
            Text(
              // Signed on purpose: which way it moved is the whole point, and
              // neither direction is coloured as good or bad — that depends on
              // a goal the app doesn't know.
              '${delta > 0 ? '+' : '−'}'
              '${formatters.decimal(delta.abs(), fractionDigits: 1)}',
              style: context.textStyles.labelMedium?.copyWith(
                color: semantic.warning,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
