import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/utils/extensions/context_extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../domain/entities/exercise.dart';
import '../../../../domain/entities/session_log.dart';
import '../../../../domain/enums/training_enums.dart';
import '../../../../domain/services/metrics_service.dart';
import '../../../../shared/l10n/exercise_name.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../../plan/presentation/widgets/plan_labels.dart';
import '../cubit/session_detail_cubit.dart';

/// One finished session, in full: the headline numbers, then every set as it
/// was logged.
///
/// Read-only. A finalized session is a record, and editing a record would take
/// the honesty out of every chart built on it (ADR §8.2).
class SessionDetailPage extends StatelessWidget {
  const SessionDetailPage({super.key, required this.sessionLogId});

  final String sessionLogId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<SessionDetailCubit>(param1: sessionLogId),
      child: const _SessionDetailView(),
    );
  }
}

class _SessionDetailView extends StatelessWidget {
  const _SessionDetailView();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return BlocBuilder<SessionDetailCubit, SessionDetailState>(
      builder: (context, state) => Scaffold(
        appBar: AppBar(
          title: Text(switch (state) {
            SessionDetailData(:final log) => Formatters.of(
              context,
            ).mediumDate(log.startedAt),
            _ => l10n.sessionDetailTitle,
          }),
        ),
        body: SafeArea(
          top: false,
          child: switch (state) {
            SessionDetailLoading() => const LoadingView(),
            SessionDetailFailure(:final failure) => ErrorView(failure: failure),
            SessionDetailMissing() => EmptyView(
              icon: Icons.search_off_rounded,
              title: l10n.sessionDetailMissingTitle,
              message: l10n.sessionDetailMissingBody,
            ),
            SessionDetailData(:final log, :final exercisesById) => _Detail(
              log: log,
              exercisesById: exercisesById,
            ),
          },
        ),
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.log, required this.exercisesById});

  final SessionLog log;
  final Map<String, Exercise> exercisesById;

  /// Exercise ids in the order they were first worked, so the page reads in
  /// the order the session actually happened rather than alphabetically.
  List<String> get _exerciseOrder {
    final seen = <String>[];
    for (final set in log.sets) {
      if (!seen.contains(set.exerciseId)) seen.add(set.exerciseId);
    }
    return seen;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final formatters = Formatters.of(context);

    // The same computation the end-of-session summary runs, so the numbers a
    // user saw when they finished are the numbers they see months later.
    // No template: the prescription that produced this session may have been
    // edited or deleted since, and measuring old work against a plan that has
    // moved would report an adherence that never happened. Everything else in
    // the summary is computed from the sets themselves.
    final summary = MetricsService.summarize(
      log: log,
      template: null,
      exercisesById: exercisesById,
    );

    final order = _exerciseOrder;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.sm,
        AppSpacing.gutter,
        AppSpacing.xxl,
      ),
      children: [
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            _Stat(
              label: l10n.summarySets(summary.completedSets),
              emphasised: true,
            ),
            _Stat(label: l10n.summaryDuration(summary.duration.inMinutes)),
            if (summary.tonnageKg > 0)
              _Stat(
                label: l10n.summaryTonnage(
                  formatters.decimal(summary.tonnageKg, fractionDigits: 0),
                ),
              ),
            if (summary.skippedSets > 0)
              _Stat(label: l10n.summarySkipped(summary.skippedSets)),
            if (log.sessionRpe case final rpe?)
              _Stat(
                label: l10n.sessionDetailRpe(
                  formatters.decimal(rpe, fractionDigits: rpe % 1 == 0 ? 0 : 1),
                ),
              ),
          ],
        ),
        if (log.notes case final notes? when notes.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          AppCard(
            elevated: false,
            color: context.colors.surfaceContainerHigh,
            child: Text(notes, style: context.textStyles.bodyMedium),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        if (order.isEmpty)
          EmptyView(
            icon: Icons.fitness_center_rounded,
            title: l10n.sessionDetailNoSetsTitle,
            message: l10n.sessionDetailNoSetsBody,
          )
        else
          for (final exerciseId in order) ...[
            _ExerciseBlock(
              exercise: exercisesById[exerciseId],
              sets: log.setsFor(exerciseId),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
      ],
    );
  }
}

class _ExerciseBlock extends StatelessWidget {
  const _ExerciseBlock({required this.exercise, required this.sets});

  /// Null if the catalog row was purged. The sets still render — a workout the
  /// user did must not disappear because its exercise did.
  final Exercise? exercise;
  final List<SetLog> sets;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final entry = exercise;

    final name = entry == null
        ? '—'
        : exerciseDisplayName(
            l10n: l10n,
            nameKey: entry.nameKey,
            customName: entry.customName,
          );

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(name, style: context.textStyles.titleSmall)),
              if (entry != null)
                Text(
                  entry.bodySection.label(l10n),
                  style: context.textStyles.labelSmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final set in sets) _SetRow(set: set),
        ],
      ),
    );
  }
}

class _SetRow extends StatelessWidget {
  const _SetRow({required this.set});

  final SetLog set;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final formatters = Formatters.of(context);
    final colors = context.colors;

    final (icon, tint) = switch (set.status) {
      SetStatus.done => (Icons.check_circle_rounded, colors.primary),
      SetStatus.partial => (
        Icons.remove_circle_outline_rounded,
        context.semanticColors.warning,
      ),
      SetStatus.skipped => (Icons.cancel_outlined, colors.error),
      SetStatus.substituted => (Icons.swap_horiz_rounded, colors.secondary),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        children: [
          Icon(icon, size: 18, color: tint),
          const SizedBox(width: AppSpacing.xs),
          SizedBox(
            width: 28,
            child: Text(
              formatters.integer(set.setIndex + 1),
              style: context.textStyles.labelMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              _describe(context, formatters),
              style: context.textStyles.bodyMedium,
            ),
          ),
          if (set.isPr)
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.xs),
              child: Text(
                l10n.sessionDetailPr,
                style: context.textStyles.labelSmall?.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Whatever the set actually recorded — weight × reps, a duration, a
  /// distance, or the reason it was skipped.
  String _describe(BuildContext context, Formatters formatters) {
    final l10n = context.l10n;

    if (set.skipReason case final reason?) return reason.label(l10n);

    final parts = <String>[];

    if (set.weightKg case final weight? when weight > 0) {
      parts.add(
        l10n.slotLoadKg(
          formatters.decimal(weight, fractionDigits: weight % 1 == 0 ? 0 : 1),
        ),
      );
    }
    if (set.reps case final reps?) parts.add(l10n.sessionDetailReps(reps));
    if (set.durationSec case final seconds?) {
      parts.add(l10n.slotDurationMinutes((seconds / 60).round()));
    }
    if (set.rpe case final rpe?) {
      parts.add(
        l10n.sessionDetailRpe(
          formatters.decimal(rpe, fractionDigits: rpe % 1 == 0 ? 0 : 1),
        ),
      );
    }

    return parts.isEmpty ? l10n.sessionDetailNoNumbers : parts.join(' · ');
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, this.emphasised = false});

  final String label;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: emphasised
            ? context.colors.primaryContainer
            : context.colors.surfaceContainerHigh,
        borderRadius: AppRadius.fullAll,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        child: Text(
          label,
          style: context.textStyles.labelLarge?.copyWith(
            color: emphasised
                ? context.colors.onPrimaryContainer
                : context.colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
