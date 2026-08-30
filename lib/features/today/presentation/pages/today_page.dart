import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/app_routes.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/utils/extensions/context_extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../domain/entities/scheduled_session.dart';
import '../../../../domain/entities/session_log.dart';
import '../../../../domain/enums/training_enums.dart';
import '../../../../domain/repositories/check_in_repository.dart';
import '../../../../domain/values/calendar_date.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/app_page.dart';
import '../../../../shared/widgets/app_sheet.dart';
import '../../../../shared/widgets/page_header.dart';
import '../../../../shared/widgets/skeleton.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../../settings/presentation/cubit/preferences_cubit.dart';
import '../../../settings/presentation/widgets/weight_sheet.dart';
import '../cubit/today_cubit.dart';

/// "Did I hit the plan today, and is the line moving?" — the question the app
/// exists to answer (ADR §9.1).
class TodayPage extends StatelessWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<TodayCubit>(),
      child: const _TodayView(),
    );
  }
}

class _TodayView extends StatelessWidget {
  const _TodayView();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final formatters = Formatters.of(context);

    return AppPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(
            l10n.todayTitle,
            subtitle: formatters.mediumDate(DateTime.now()),
          ),
          Expanded(
            child: BlocBuilder<TodayCubit, TodayState>(
              builder: (context, state) => AnimatedSwitcher(
                duration: AppDurations.base,
                child: switch (state) {
                  TodayLoading() => const Shimmer(
                    key: ValueKey('loading'),
                    child: Column(
                      children: [
                        SkeletonCard(height: 168),
                        SizedBox(height: AppSpacing.sm),
                        SkeletonCard(height: 96),
                      ],
                    ),
                  ),
                  TodayFailure(:final failure) => ErrorView(
                    key: const ValueKey('error'),
                    failure: failure,
                  ),
                  TodayData() => _TodayBody(
                    key: const ValueKey('data'),
                    state: state,
                  ),
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TodayBody extends StatelessWidget {
  const _TodayBody({super.key, required this.state});

  final TodayData state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
      children: [
        _SessionCard(state: state),
        if (state.checkInDue) ...[
          const SizedBox(height: AppSpacing.sm),
          const _CheckInPrompt(),
        ],
        const SizedBox(height: AppSpacing.lg),
        if (state.week.isNotEmpty) ...[
          Text(
            l10n.todayWeekLabel,
            style: context.textStyles.labelMedium?.copyWith(
              color: context.colors.onSurfaceVariant,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          _WeekStrip(days: state.week),
        ],
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.todayLastSession,
                style: context.textStyles.labelMedium?.copyWith(
                  color: context.colors.onSurfaceVariant,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton(
              onPressed: () => context.push(AppRoutes.history),
              child: Text(l10n.todayViewHistory),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        _LastSessionCard(session: state.lastSession),
      ],
    );
  }
}

/// The card above the fold: what today is, and the one action it wants.
class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.state});

  final TodayData state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    if (state.program == null) {
      return _MessageCard(
        icon: Icons.event_note_rounded,
        title: l10n.todayNoProgramTitle,
        body: l10n.todayNoProgramBody,
        actionLabel: l10n.planCreateProgram,
        onAction: () => context.go(AppRoutes.plan),
      );
    }

    final today = state.today;
    if (today == null) {
      return _MessageCard(
        icon: Icons.calendar_month_outlined,
        title: l10n.todayNoScheduleTitle,
        body: l10n.todayNoScheduleBody,
        actionLabel: l10n.scheduleCommit,
        onAction: () => context.go(AppRoutes.plan),
      );
    }

    return switch (today.kind) {
      // A rest day gets a deliberately calm empty state, not a nag
      // (ADR §9.1).
      ScheduledSessionKind.rest => _MessageCard(
        icon: Icons.bedtime_outlined,
        title: l10n.todayRestDayTitle,
        body: l10n.todayRestDayBody,
      ),
      ScheduledSessionKind.cricket => _MessageCard(
        icon: Icons.sports_cricket_rounded,
        title: l10n.todayCricketTitle,
        body: l10n.todayCricketBody,
      ),
      ScheduledSessionKind.custom => _MessageCard(
        icon: Icons.directions_walk_rounded,
        title: l10n.todayCricketTitle,
        body: l10n.todayCricketBody,
      ),
      ScheduledSessionKind.gym => _GymDayCard(state: state, today: today),
    };
  }
}

class _GymDayCard extends StatelessWidget {
  const _GymDayCard({required this.state, required this.today});

  final TodayData state;
  final ScheduledSession today;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final template = state.template;
    final isRunning = state.activeSession?.scheduledSessionId == today.id;
    final isDone = today.status == ScheduledSessionStatus.completed;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (template != null) _CodeBadge(code: template.code),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  template?.title ?? l10n.todayTitle,
                  style: context.textStyles.titleLarge,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isRunning)
                _Pill(label: l10n.todayInProgress, emphasised: true),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              if (template != null)
                _Pill(label: l10n.todayBlockCount(template.blocks.length)),
              if (template != null)
                _Pill(label: l10n.sessionSetCount(template.totalSets)),
              if (today.plannedDurationMin case final minutes?)
                _Pill(label: l10n.todayEstimatedMinutes(minutes)),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton.icon(
            onPressed: isDone
                ? null
                : () => context.push(AppRoutes.activeSession(today.id)),
            icon: Icon(
              isRunning
                  ? Icons.play_arrow_rounded
                  : Icons.fitness_center_rounded,
            ),
            label: Text(
              isRunning ? l10n.todayResumeSession : l10n.todayStartSession,
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 28, color: context.colors.onSurfaceVariant),
          const SizedBox(height: AppSpacing.sm),
          Text(title, style: context.textStyles.titleMedium),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            body,
            style: context.textStyles.bodyMedium?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

/// Seven days around today, coloured by what each one is.
class _WeekStrip extends StatelessWidget {
  const _WeekStrip({required this.days});

  final List<ScheduledSession> days;

  @override
  Widget build(BuildContext context) {
    final formatters = Formatters.of(context);
    final today = CalendarDate.today();

    return Row(
      children: [
        for (final day in days)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: _DayCell(
                day: day,
                isToday: day.date == today,
                weekday: formatters.shortWeekday(day.date.toDateTime()),
                dayOfMonth: formatters.integer(day.date.day),
              ),
            ),
          ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.isToday,
    required this.weekday,
    required this.dayOfMonth,
  });

  final ScheduledSession day;
  final bool isToday;
  final String weekday;
  final String dayOfMonth;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final semantic = context.semanticColors;

    // Status leads, kind follows: what happened matters more than what was
    // planned once the day is past.
    final (background, foreground) = switch (day.status) {
      ScheduledSessionStatus.completed => (colors.primary, colors.onPrimary),
      ScheduledSessionStatus.partial => (
        semantic.warningContainer,
        semantic.onWarningContainer,
      ),
      ScheduledSessionStatus.skipped => (
        colors.errorContainer,
        colors.onErrorContainer,
      ),
      ScheduledSessionStatus.inProgress => (
        colors.primaryContainer,
        colors.onPrimaryContainer,
      ),
      ScheduledSessionStatus.upcoming => switch (day.kind) {
        ScheduledSessionKind.gym => (
          colors.surfaceContainerHighest,
          colors.onSurface,
        ),
        _ => (colors.surfaceContainerHigh, colors.onSurfaceVariant),
      },
    };

    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadius.mdAll,
        border: isToday ? Border.all(color: colors.primary, width: 2) : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            weekday,
            style: context.textStyles.labelSmall?.copyWith(
              color: foreground.withValues(alpha: 0.75),
            ),
          ),
          Text(
            dayOfMonth,
            style: context.textStyles.labelLarge?.copyWith(
              color: foreground,
              fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Asks for a bodyweight once a training cycle has ended.
///
/// Appears on Today rather than only in the Profile tab because a check-in
/// nobody is prompted for is a check-in nobody records, and the weight series
/// is what every trend in Insights is built on.
class _CheckInPrompt extends StatelessWidget {
  const _CheckInPrompt();

  Future<void> _record(BuildContext context) async {
    final repository = getIt<CheckInRepository>();
    final unitSystem = context
        .read<PreferencesCubit>()
        .state
        .preferences
        .unitSystem;

    final current = await repository.watchLatestWeight().first;
    if (!context.mounted) return;

    final result = await AppSheet.show<double>(
      context,
      builder: (_) =>
          WeightSheet(initialKg: current?.weightKg, unitSystem: unitSystem),
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

    return AppCard(
      color: context.colors.secondaryContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.monitor_weight_outlined,
                color: context.colors.onSecondaryContainer,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  l10n.todayCheckInTitle,
                  style: context.textStyles.titleSmall?.copyWith(
                    color: context.colors.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.todayCheckInBody,
            style: context.textStyles.bodyMedium?.copyWith(
              color: context.colors.onSecondaryContainer,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonal(
              onPressed: () => _record(context),
              child: Text(l10n.todayCheckInAction),
            ),
          ),
        ],
      ),
    );
  }
}

class _LastSessionCard extends StatelessWidget {
  const _LastSessionCard({required this.session});

  final SessionLog? session;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final formatters = Formatters.of(context);
    final last = session;

    if (last == null || last.isActive) {
      return AppCard(
        elevated: false,
        color: context.colors.surfaceContainerHigh,
        child: Text(
          l10n.todayLastSessionNone,
          style: context.textStyles.bodyMedium?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
      );
    }

    return AppCard(
      // The recap was a dead end before: it showed three numbers with no way
      // to see what they were made of.
      onTap: () => context.push(AppRoutes.sessionDetail(last.id)),
      child: Row(
        children: [
          Expanded(
            child: Text(
              formatters.mediumDate(last.startedAt),
              style: context.textStyles.bodyLarge,
            ),
          ),
          _Pill(label: l10n.summarySets(last.completedSets)),
          const SizedBox(width: AppSpacing.xs),
          _Pill(label: l10n.summaryDuration(last.duration.inMinutes)),
          const SizedBox(width: AppSpacing.xxs),
          Icon(
            Icons.chevron_right_rounded,
            color: context.colors.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

class _CodeBadge extends StatelessWidget {
  const _CodeBadge({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.colors.primary,
        borderRadius: AppRadius.mdAll,
      ),
      child: Text(
        code,
        style: context.textStyles.titleMedium?.copyWith(
          color: context.colors.onPrimary,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, this.emphasised = false});

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
          vertical: AppSpacing.xxs + 2,
        ),
        child: Text(
          label,
          style: context.textStyles.labelMedium?.copyWith(
            color: emphasised
                ? context.colors.onPrimaryContainer
                : context.colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
