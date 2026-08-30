import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/utils/extensions/context_extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../domain/entities/app_preferences.dart';
import '../../../../domain/entities/check_in.dart';
import '../../../../domain/repositories/check_in_repository.dart';
import '../../../../domain/values/body_metrics.dart';
import '../../../../domain/values/calendar_date.dart';
import '../../../../shared/l10n/body_format.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/app_sheet.dart';
import '../cubit/preferences_cubit.dart';
import 'body_labels.dart';
import 'height_sheet.dart';
import 'weight_sheet.dart';

/// Gender, height, current weight and the BMI that falls out of them.
///
/// Height and gender are standing facts and live in preferences. Weight is a
/// time series and lives in `check_ins`, so the number here is the latest
/// point on a trend rather than a field that gets overwritten.
class BodyCard extends StatelessWidget {
  const BodyCard({super.key, required this.preferences});

  final AppPreferences preferences;

  Future<void> _editHeight(BuildContext context) async {
    final result = await AppSheet.show<double?>(
      context,
      builder: (_) => HeightSheet(
        initialCm: preferences.heightCm,
        unitSystem: preferences.unitSystem,
      ),
    );
    if (result == null || !context.mounted) return;

    await context.read<PreferencesCubit>().setHeightCm(
      // The sheet reports a negative to mean "clear it", because null is
      // already how it reports a cancelled sheet.
      result.isNegative ? null : result,
    );
  }

  Future<void> _recordWeight(BuildContext context, double? currentKg) async {
    final repository = getIt<CheckInRepository>();

    final result = await AppSheet.show<double>(
      context,
      builder: (_) =>
          WeightSheet(initialKg: currentKg, unitSystem: preferences.unitSystem),
    );
    if (result == null || !context.mounted) return;

    final recorded = await repository.record(
      date: CalendarDate.today(),
      weightKg: result,
    );
    if (!context.mounted) return;

    if (recorded.failureOrNull != null) {
      context.showSnackBar(context.l10n.stateErrorBody, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return StreamBuilder<CheckIn?>(
      stream: getIt<CheckInRepository>().watchLatestWeight(),
      builder: (context, snapshot) {
        final weightKg = snapshot.data?.weightKg;
        final bmi = Bmi.calculate(
          weightKg: weightKg,
          heightCm: preferences.heightCm,
        );

        return AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.profileBodyTitle, style: context.textStyles.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              _UnitToggle(
                selected: preferences.unitSystem,
                onChanged: (system) =>
                    context.read<PreferencesCubit>().setUnitSystem(system),
              ),
              const SizedBox(height: AppSpacing.sm),
              _GenderChips(
                selected: preferences.gender,
                onChanged: (gender) =>
                    context.read<PreferencesCubit>().setGender(gender),
              ),
              const Divider(height: AppSpacing.lg),
              _MeasurementRow(
                label: l10n.profileHeightLabel,
                value: preferences.heightCm == null
                    ? null
                    : formatHeight(
                        context,
                        cm: preferences.heightCm!,
                        unitSystem: preferences.unitSystem,
                      ),
                onTap: () => _editHeight(context),
              ),
              _MeasurementRow(
                label: l10n.profileWeightLabel,
                value: weightKg == null
                    ? null
                    : formatWeight(
                        context,
                        kg: weightKg,
                        unitSystem: preferences.unitSystem,
                      ),
                onTap: () => _recordWeight(context, weightKg),
              ),
              const Divider(height: AppSpacing.lg),
              _BmiRow(bmi: bmi),
            ],
          ),
        );
      },
    );
  }
}

class _UnitToggle extends StatelessWidget {
  const _UnitToggle({required this.selected, required this.onChanged});

  final UnitSystem selected;
  final ValueChanged<UnitSystem> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<UnitSystem>(
        segments: [
          ButtonSegment(
            value: UnitSystem.metric,
            label: Text(l10n.unitsMetric),
          ),
          ButtonSegment(
            value: UnitSystem.imperial,
            label: Text(l10n.unitsImperial),
          ),
        ],
        selected: {selected},
        showSelectedIcon: false,
        onSelectionChanged: (selection) => onChanged(selection.first),
      ),
    );
  }
}

class _GenderChips extends StatelessWidget {
  const _GenderChips({required this.selected, required this.onChanged});

  final Gender selected;
  final ValueChanged<Gender> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        for (final gender in Gender.values)
          ChoiceChip(
            label: Text(gender.label(l10n)),
            selected: selected == gender,
            onSelected: (_) => onChanged(gender),
          ),
      ],
    );
  }
}

class _MeasurementRow extends StatelessWidget {
  const _MeasurementRow({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;

  /// Null renders the "not set" affordance rather than an empty row, so an
  /// unfilled measurement reads as something to tap.
  final String? value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final current = value;

    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.smAll,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: [
            Expanded(child: Text(label, style: context.textStyles.bodyMedium)),
            Text(
              current ?? l10n.profileNotSet,
              style: context.textStyles.bodyLarge?.copyWith(
                fontWeight: current == null ? FontWeight.w400 : FontWeight.w600,
                color: current == null
                    ? context.colors.onSurfaceVariant
                    : context.colors.onSurface,
              ),
            ),
            const SizedBox(width: AppSpacing.xxs),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: context.colors.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _BmiRow extends StatelessWidget {
  const _BmiRow({required this.bmi});

  final double? bmi;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final formatters = Formatters.of(context);
    final value = bmi;
    final band = Bmi.bandFor(value);

    if (value == null || band == null) {
      // Says which input is missing rather than showing a blank number.
      return Text(
        l10n.profileBmiUnavailable,
        style: context.textStyles.bodySmall?.copyWith(
          color: context.colors.onSurfaceVariant,
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: Text(
            l10n.profileBmiLabel,
            style: context.textStyles.bodyMedium,
          ),
        ),
        Text(
          formatters.decimal(value, fractionDigits: 1),
          style: context.textStyles.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        DecoratedBox(
          decoration: BoxDecoration(
            color: band.containerColor(context),
            borderRadius: AppRadius.fullAll,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xs,
              vertical: AppSpacing.xxs,
            ),
            child: Text(
              band.label(l10n),
              style: context.textStyles.labelSmall?.copyWith(
                color: band.onContainerColor(context),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
