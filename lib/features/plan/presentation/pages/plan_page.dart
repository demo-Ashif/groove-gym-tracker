import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/app_routes.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/utils/extensions/context_extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../domain/entities/plan.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/app_page.dart';
import '../../../../shared/widgets/app_sheet.dart';
import '../../../../shared/widgets/page_header.dart';
import '../../../../shared/widgets/skeleton.dart';
import '../../../../shared/widgets/state_views.dart';
import '../cubit/plan_list_cubit.dart';
import '../cubit/plan_list_state.dart';
import '../widgets/program_form_sheet.dart';

/// The Plan tab: every program, with the active one first (ADR §15
/// `features/plan`).
class PlanPage extends StatelessWidget {
  const PlanPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<PlanListCubit>(),
      child: const _PlanView(),
    );
  }
}

class _PlanView extends StatelessWidget {
  const _PlanView();

  Future<void> _createProgram(BuildContext context) async {
    final cubit = context.read<PlanListCubit>();

    final result = await AppSheet.show<ProgramFormResult>(
      context,
      builder: (_) => const ProgramFormSheet(),
    );
    if (result == null || !context.mounted) return;

    final failure = await cubit.createProgram(
      name: result.name,
      startDate: result.startDate,
    );
    if (failure != null && context.mounted) {
      context.showSnackBar(context.l10n.stateErrorBody, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return AppPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(
            l10n.planTitle,
            trailing: TextButton.icon(
              onPressed: () => _createProgram(context),
              icon: const Icon(Icons.add_rounded, size: 20),
              label: Text(l10n.planCreateProgram),
            ),
          ),
          Expanded(
            child: BlocBuilder<PlanListCubit, PlanListState>(
              builder: (context, state) => AnimatedSwitcher(
                duration: AppDurations.base,
                switchInCurve: AppMotion.standard,
                child: switch (state) {
                  PlanListLoading() => const _PlanSkeleton(
                    key: ValueKey('loading'),
                  ),
                  PlanListFailure(:final failure) => ErrorView(
                    key: const ValueKey('error'),
                    failure: failure,
                  ),
                  PlanListData(:final programs) when programs.isEmpty =>
                    EmptyView(
                      key: const ValueKey('empty'),
                      icon: Icons.event_note_rounded,
                      title: l10n.planPlaceholderTitle,
                      message: l10n.planPlaceholderBody,
                      actionLabel: l10n.planCreateProgram,
                      onAction: () => _createProgram(context),
                    ),
                  PlanListData(:final programs) => _ProgramList(
                    key: const ValueKey('data'),
                    programs: programs,
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

class _ProgramList extends StatelessWidget {
  const _ProgramList({super.key, required this.programs});

  final List<Program> programs;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
      itemCount: programs.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) => _ProgramCard(program: programs[index]),
    );
  }
}

class _ProgramCard extends StatelessWidget {
  const _ProgramCard({required this.program});

  final Program program;

  Future<void> _delete(BuildContext context) async {
    final cubit = context.read<PlanListCubit>();
    final l10n = context.l10n;

    final confirmed = await confirm(
      context,
      title: l10n.programDeleteTitle,
      message: l10n.programDeleteBody,
      confirmLabel: l10n.commonDelete,
    );
    if (!confirmed) return;

    final failure = await cubit.delete(program.id);
    if (failure != null && context.mounted) {
      context.showSnackBar(l10n.stateErrorBody, isError: true);
    }
  }

  Future<void> _setActive(BuildContext context) async {
    final failure = await context.read<PlanListCubit>().setActive(program.id);
    if (failure != null && context.mounted) {
      context.showSnackBar(context.l10n.stateErrorBody, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final formatters = Formatters.of(context);

    return AppCard(
      onTap: () => context.push(AppRoutes.programEditor(program.id)),
      semanticLabel: program.name,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  program.name,
                  style: context.textStyles.titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (program.isActive) const _ActiveBadge(),
              _ProgramMenu(
                isActive: program.isActive,
                onSetActive: () => _setActive(context),
                onDelete: () => _delete(context),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            l10n.planStartsOn(
              formatters.mediumDate(program.startDate.toDateTime()),
            ),
            style: context.textStyles.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              _MetaPill(label: l10n.planWeekCount(program.weekCount)),
              const SizedBox(width: AppSpacing.xs),
              _MetaPill(
                label: l10n.planSessionCount(program.sessionTemplateCount),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActiveBadge extends StatelessWidget {
  const _ActiveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: AppSpacing.xxs),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: context.colors.primary,
        borderRadius: AppRadius.fullAll,
      ),
      child: Text(
        context.l10n.planActiveBadge,
        style: context.textStyles.labelSmall?.copyWith(
          color: context.colors.onPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.surfaceContainerHigh,
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
            color: context.colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _ProgramMenu extends StatelessWidget {
  const _ProgramMenu({
    required this.isActive,
    required this.onSetActive,
    required this.onDelete,
  });

  final bool isActive;
  final VoidCallback onSetActive;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return PopupMenuButton<void>(
      icon: const Icon(Icons.more_vert_rounded, size: 20),
      tooltip: l10n.commonEdit,
      itemBuilder: (context) => [
        if (!isActive)
          PopupMenuItem<void>(
            onTap: onSetActive,
            child: Text(l10n.programSetActive),
          ),
        PopupMenuItem<void>(
          onTap: onDelete,
          child: Text(
            l10n.commonDelete,
            style: TextStyle(color: context.colors.error),
          ),
        ),
      ],
    );
  }
}

/// Content-shaped placeholder: three program cards at the size the real ones
/// land at, so nothing jumps when the query answers.
class _PlanSkeleton extends StatelessWidget {
  const _PlanSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Shimmer(
      child: Column(
        children: [
          SkeletonCard(height: 116),
          SizedBox(height: AppSpacing.sm),
          SkeletonCard(height: 116),
          SizedBox(height: AppSpacing.sm),
          SkeletonCard(height: 116),
        ],
      ),
    );
  }
}
