import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/app_routes.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/utils/extensions/context_extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../domain/entities/session_log.dart';
import '../../../../domain/repositories/log_repository.dart';
import '../../../../domain/repositories/schedule_repository.dart';
import '../../../../domain/values/calendar_date.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/state_views.dart';
import '../cubit/history_cubit.dart';

/// Every finished session, newest first.
///
/// Read-only: a finalized session is history, and history must not lie
/// (ADR §8.2). Tapping a row opens it in full.
class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<HistoryCubit>(),
      child: const _HistoryView(),
    );
  }
}

class _HistoryView extends StatelessWidget {
  const _HistoryView();

  /// Creates a day outside any program and opens the logger on it.
  ///
  /// Refused while another session is unfinished: the logging screen resumes
  /// "the" active session, so a second one would have the two fighting over
  /// the same screen.
  Future<void> _addPastSession(BuildContext context) async {
    final l10n = context.l10n;
    final scheduleRepository = getIt<ScheduleRepository>();

    final running = await getIt<LogRepository>().watchActiveSession().first;
    if (!context.mounted) return;
    if (running != null) {
      context.showSnackBar(l10n.historyFinishCurrentFirst, isError: true);
      return;
    }

    final today = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: today.subtract(const Duration(days: 1)),
      // A year back covers "I've been training a month already" with room to
      // spare; the future is closed off because this is for what happened.
      firstDate: DateTime(today.year - 1, today.month, today.day),
      lastDate: today,
      helpText: l10n.historyAddPastSession,
    );
    if (picked == null || !context.mounted) return;

    final day = await scheduleRepository.createBackfillDay(
      date: CalendarDate.from(picked),
    );
    if (!context.mounted) return;

    switch (day.dataOrNull) {
      case final scheduled?:
        await context.push(AppRoutes.activeSession(scheduled.id));
      case null:
        context.showSnackBar(l10n.stateErrorBody, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.historyTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addPastSession(context),
        icon: const Icon(Icons.history_toggle_off_rounded),
        label: Text(l10n.historyAddPastSession),
      ),
      body: SafeArea(
        top: false,
        child: BlocBuilder<HistoryCubit, HistoryState>(
          builder: (context, state) => switch (state) {
            HistoryLoading() => const LoadingView(),
            HistoryFailure(:final failure) => ErrorView(failure: failure),
            HistoryData(:final sessions) when sessions.isEmpty => EmptyView(
              icon: Icons.history_rounded,
              title: l10n.historyEmptyTitle,
              message: l10n.historyEmptyBody,
            ),
            HistoryData(:final sessions) => ListView.builder(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.gutter,
                AppSpacing.xs,
                AppSpacing.gutter,
                AppSpacing.xxl,
              ),
              itemCount: sessions.length,
              itemBuilder: (context, index) =>
                  _HistoryRow(entry: sessions[index]),
            ),
          },
        ),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry});

  final SessionHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final formatters = Formatters.of(context);
    final log = entry.log;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: AppCard(
        onTap: () => context.push(AppRoutes.sessionDetail(log.id)),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    // A session with no template behind it — a cricket day
                    // someone lifted on — still belongs here, under its date.
                    entry.title ?? formatters.mediumDate(log.startedAt),
                    style: context.textStyles.titleSmall,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatters.mediumDate(log.startedAt),
                    style: context.textStyles.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            _Pill(label: l10n.summarySets(log.completedSets)),
            const SizedBox(width: AppSpacing.xs),
            _Pill(label: l10n.summaryDuration(log.duration.inMinutes)),
            const SizedBox(width: AppSpacing.xxs),
            Icon(
              Icons.chevron_right_rounded,
              color: context.colors.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerHighest,
        borderRadius: AppRadius.fullAll,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: AppSpacing.xxs,
        ),
        child: Text(
          label,
          style: context.textStyles.labelMedium?.copyWith(
            color: context.colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
