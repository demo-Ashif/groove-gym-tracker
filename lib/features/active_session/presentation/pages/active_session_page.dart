import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/haptics/app_haptics.dart';
import '../../../../core/utils/extensions/context_extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../domain/entities/exercise.dart';
import '../../../../domain/entities/plan.dart';
import '../../../../domain/entities/session_log.dart';
import '../../../../domain/enums/training_enums.dart';
import '../../../../shared/l10n/exercise_name.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/app_sheet.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../../plan/presentation/widgets/plan_labels.dart';
import '../cubit/active_session_cubit.dart';
import '../cubit/active_session_state.dart';
import '../widgets/rest_timer_bar.dart';
import '../widgets/set_chip.dart';
import '../widgets/set_editor_sheet.dart';
import 'finalize_sheet.dart';

/// The core screen (ADR §9.2): blocks stacked, set chips tapped, nothing
/// typed.
class ActiveSessionPage extends StatelessWidget {
  const ActiveSessionPage({super.key, required this.scheduledSessionId});

  final String scheduledSessionId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<ActiveSessionCubit>(param1: scheduledSessionId),
      child: const _ActiveSessionView(),
    );
  }
}

class _ActiveSessionView extends StatelessWidget {
  const _ActiveSessionView();

  Future<void> _finish(BuildContext context) async {
    final cubit = context.read<ActiveSessionCubit>();
    final state = cubit.state;
    if (state is! ActiveSessionData) return;

    final result = await AppSheet.show<FinalizeResult>(
      context,
      builder: (_) => const FinalizeSheet(),
    );
    if (result == null || !context.mounted) return;

    final failure = await cubit.finalizeSession(
      sessionRpe: result.sessionRpe,
      energy: result.energy,
      notes: result.notes,
    );

    if (!context.mounted) return;
    if (failure != null) {
      context.showSnackBar(context.l10n.stateErrorBody, isError: true);
      return;
    }

    getIt<AppHaptics>().medium();
    // The cubit's stream reports the session gone and the page pops itself;
    // the summary is shown on the way out.
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => SessionSummarySheet(
        log: state.log,
        template: state.template,
        exercisesById: state.exercisesById,
      ),
    );
  }

  Future<void> _discard(BuildContext context) async {
    final cubit = context.read<ActiveSessionCubit>();
    final l10n = context.l10n;

    final confirmed = await confirm(
      context,
      title: l10n.sessionDiscardTitle,
      message: l10n.sessionDiscardBody,
      confirmLabel: l10n.sessionDiscard,
    );
    if (!confirmed) return;

    final failure = await cubit.discardSession();
    if (failure != null && context.mounted) {
      context.showSnackBar(l10n.stateErrorBody, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return BlocConsumer<ActiveSessionCubit, ActiveSessionState>(
      listenWhen: (_, current) => current is ActiveSessionFinished,
      listener: (context, _) {
        if (context.canPop()) context.pop();
      },
      builder: (context, state) => Scaffold(
        appBar: AppBar(
          title: Text(switch (state) {
            ActiveSessionData(:final template) => template?.title ?? '',
            _ => '',
          }),
          actions: [
            if (state is ActiveSessionData)
              PopupMenuButton<void>(
                icon: const Icon(Icons.more_vert_rounded),
                itemBuilder: (context) => [
                  PopupMenuItem<void>(
                    onTap: () => _discard(context),
                    child: Text(
                      l10n.sessionDiscard,
                      style: TextStyle(color: context.colors.error),
                    ),
                  ),
                ],
              ),
          ],
          bottom: switch (state) {
            ActiveSessionData(:final restStartedAt?, :final restSeconds) =>
              PreferredSize(
                preferredSize: const Size.fromHeight(44),
                child: RestTimerBar(
                  startedAt: restStartedAt,
                  totalSeconds: restSeconds,
                  onDismiss: context.read<ActiveSessionCubit>().dismissRest,
                ),
              ),
            _ => null,
          },
        ),
        floatingActionButton: state is ActiveSessionData
            ? FloatingActionButton.extended(
                onPressed: () => _finish(context),
                icon: const Icon(Icons.check_rounded),
                label: Text(l10n.sessionFinish),
              )
            : null,
        body: SafeArea(
          top: false,
          child: switch (state) {
            ActiveSessionLoading() => const LoadingView(),
            ActiveSessionFailure(:final failure) => ErrorView(failure: failure),
            ActiveSessionFinished() => const SizedBox.shrink(),
            ActiveSessionData() => _BlockList(state: state),
          },
        ),
      ),
    );
  }
}

class _BlockList extends StatelessWidget {
  const _BlockList({required this.state});

  final ActiveSessionData state;

  @override
  Widget build(BuildContext context) {
    final blocks = state.template?.blocks ?? const <BlockTemplate>[];

    if (blocks.isEmpty) {
      return EmptyView(
        icon: Icons.fitness_center_rounded,
        title: context.l10n.sessionNoBlocksTitle,
        message: context.l10n.sessionNoBlocksBody,
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.xs,
        AppSpacing.gutter,
        AppSpacing.xxl * 2,
      ),
      children: [
        for (final block in blocks) ...[
          _BlockCard(block: block, state: state),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}

class _BlockCard extends StatelessWidget {
  const _BlockCard({required this.block, required this.state});

  final BlockTemplate block;
  final ActiveSessionData state;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(block.title, style: context.textStyles.titleMedium),
              ),
              Text(
                block.kind.label(context.l10n),
                style: context.textStyles.labelMedium?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          for (final slot in block.exercises) ...[
            const SizedBox(height: AppSpacing.md),
            _ExerciseRow(slot: slot, state: state),
          ],
        ],
      ),
    );
  }
}

class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow({required this.slot, required this.state});

  final ExerciseTemplate slot;
  final ActiveSessionData state;

  Exercise? get _exercise => state.exercisesById[slot.exerciseId];

  List<SetLog?> get _sets {
    final logged = {
      for (final set in state.log.sets)
        if (set.exerciseId == slot.exerciseId) set.setIndex: set,
    };
    // The grid is as long as the prescription, plus anything logged beyond it.
    final length = [
      slot.targetSets,
      ...logged.keys.map((index) => index + 1),
    ].reduce((a, b) => a > b ? a : b);

    return List.generate(length, (index) => logged[index]);
  }

  int? get _activeIndex {
    final sets = _sets;
    for (var index = 0; index < sets.length; index++) {
      if (sets[index] == null) return index;
    }
    return null;
  }

  Future<void> _tap(BuildContext context, int index, SetLog? existing) async {
    final cubit = context.read<ActiveSessionCubit>();

    // An already-logged chip opens the editor rather than silently rewriting
    // itself — a mis-tap must be correctable, not destructive.
    if (existing != null) {
      await _edit(context, index, existing);
      return;
    }

    getIt<AppHaptics>().selection();
    final failure = await cubit.logSet(slot: slot, setIndex: index);
    if (failure != null && context.mounted) {
      context.showSnackBar(context.l10n.stateErrorBody, isError: true);
    }
  }

  Future<void> _edit(BuildContext context, int index, SetLog? existing) async {
    final cubit = context.read<ActiveSessionCubit>();
    final exercise = _exercise;
    final prefill = cubit.prefillFor(slot, index);

    final result = await AppSheet.show<SetEditorResult>(
      context,
      builder: (_) => SetEditorSheet(
        setIndex: index,
        isUnilateral: exercise?.isUnilateral ?? false,
        weightStepKg: exercise?.loadType.defaultIncrementKg ?? 2.5,
        existing: existing,
        prefillWeightKg: prefill.weightKg,
        prefillReps: prefill.reps,
      ),
    );
    if (result == null || !context.mounted) return;

    if (result.clear) {
      if (existing != null) await cubit.clearSet(existing.id);
      return;
    }

    final failure = await cubit.logSet(
      slot: slot,
      setIndex: index,
      weightKg: result.weightKg,
      reps: result.reps,
      rpe: result.rpe,
      side: result.side,
    );
    if (failure != null && context.mounted) {
      context.showSnackBar(context.l10n.stateErrorBody, isError: true);
    }
  }

  Future<void> _skip(BuildContext context, int index) async {
    final cubit = context.read<ActiveSessionCubit>();

    final reason = await showModalBottomSheet<SkipReason>(
      context: context,
      useSafeArea: true,
      builder: (_) => const SkipReasonSheet(),
    );
    if (reason == null || !context.mounted) return;

    final failure = await cubit.skipSet(
      slot: slot,
      setIndex: index,
      reason: reason,
    );
    if (failure != null && context.mounted) {
      context.showSnackBar(context.l10n.stateErrorBody, isError: true);
    }
  }

  Future<void> _allAsPlanned(BuildContext context) async {
    final cubit = context.read<ActiveSessionCubit>();
    getIt<AppHaptics>().light();

    final failure = await cubit.logAllAsPlanned(slot);
    if (failure != null && context.mounted) {
      context.showSnackBar(context.l10n.stateErrorBody, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final formatters = Formatters.of(context);
    final exercise = _exercise;
    final sets = _sets;
    final active = _activeIndex;
    final previous = state.previousSets[slot.exerciseId];

    final name = exercise == null
        ? '—'
        : exerciseDisplayName(
            l10n: l10n,
            nameKey: exercise.nameKey,
            customName: exercise.customName,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(name, style: context.textStyles.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    previous == null
                        ? l10n.sessionNoPrevious
                        : l10n.sessionPreviousSet(
                            formatters.decimal(
                              previous.weightKg ?? 0,
                              fractionDigits: (previous.weightKg ?? 0) % 1 == 0
                                  ? 0
                                  : 1,
                            ),
                            previous.reps ?? 0,
                          ),
                    style: context.textStyles.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              l10n.sessionSetProgress(
                sets.where((set) => set?.isCompleted ?? false).length,
                slot.targetSets,
              ),
              style: context.textStyles.labelLarge?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (var index = 0; index < sets.length; index++)
              // Swipe left to skip (ADR §9.2). The chip stays tappable, so the
              // gesture adds a path rather than replacing one.
              Dismissible(
                key: ValueKey('${slot.id}-$index'),
                direction: DismissDirection.endToStart,
                confirmDismiss: (_) async {
                  await _skip(context, index);
                  // Never actually dismissed: the chip is rewritten in place
                  // by the query, not removed from the list.
                  return false;
                },
                background: const SizedBox.shrink(),
                child: SetChip(
                  setIndex: index,
                  set: sets[index],
                  isActive: index == active,
                  onTap: () => _tap(context, index, sets[index]),
                  onLongPress: () => _edit(context, index, sets[index]),
                ),
              ),
            if (active != null)
              TextButton(
                onPressed: () => _allAsPlanned(context),
                child: Text(l10n.sessionAllAsPlanned),
              ),
          ],
        ),
      ],
    );
  }
}
