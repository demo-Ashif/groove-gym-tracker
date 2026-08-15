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
import '../../../../shared/l10n/exercise_name.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../shared/widgets/app_sheet.dart';
import '../../../../shared/widgets/skeleton.dart';
import '../../../../shared/widgets/state_views.dart';
import '../cubit/session_editor_cubit.dart';
import '../cubit/session_editor_state.dart';
import '../widgets/block_form_sheet.dart';
import '../widgets/exercise_picker_sheet.dart';
import '../widgets/plan_labels.dart';
import '../widgets/slot_form_sheet.dart';

/// Builds one training day: its blocks, and the exercises prescribed in each.
class SessionEditorPage extends StatelessWidget {
  const SessionEditorPage({
    super.key,
    required this.programId,
    required this.sessionId,
  });

  final String programId;
  final String sessionId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          getIt<SessionEditorCubit>(param1: programId, param2: sessionId),
      child: const _SessionEditorView(),
    );
  }
}

class _SessionEditorView extends StatelessWidget {
  const _SessionEditorView();

  Future<void> _addBlock(BuildContext context) async {
    final cubit = context.read<SessionEditorCubit>();

    final result = await AppSheet.show<BlockFormResult>(
      context,
      builder: (_) => const BlockFormSheet(),
    );
    if (result == null || !context.mounted) return;

    final failure = await cubit.addBlock(
      kind: result.kind,
      title: result.title,
    );
    if (failure != null && context.mounted) {
      context.showSnackBar(context.l10n.stateErrorBody, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return BlocConsumer<SessionEditorCubit, SessionEditorState>(
      listenWhen: (_, current) => current is SessionEditorGone,
      listener: (context, _) {
        if (context.canPop()) context.pop();
      },
      builder: (context, state) => Scaffold(
        appBar: AppBar(
          title: Text(switch (state) {
            SessionEditorData(:final session) => session.title,
            _ => l10n.planTitle,
          }),
          bottom: switch (state) {
            SessionEditorData(:final session) => PreferredSize(
              preferredSize: const Size.fromHeight(28),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(
                    start: AppSpacing.md,
                    bottom: AppSpacing.xs,
                  ),
                  child: Text(
                    l10n.sessionSetCount(session.totalSets),
                    style: context.textStyles.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
            _ => null,
          },
        ),
        floatingActionButton: state is SessionEditorData
            ? FloatingActionButton.extended(
                onPressed: () => _addBlock(context),
                icon: const Icon(Icons.add_rounded),
                label: Text(l10n.sessionAddBlock),
              )
            : null,
        body: SafeArea(
          top: false,
          child: switch (state) {
            SessionEditorLoading() => const Padding(
              padding: EdgeInsets.all(AppSpacing.gutter),
              child: Shimmer(
                child: Column(
                  children: [
                    SkeletonCard(height: 160),
                    SizedBox(height: AppSpacing.sm),
                    SkeletonCard(height: 160),
                  ],
                ),
              ),
            ),
            SessionEditorFailure(:final failure) => ErrorView(failure: failure),
            SessionEditorGone() => const SizedBox.shrink(),
            SessionEditorData(:final session) when session.blocks.isEmpty =>
              EmptyView(
                icon: Icons.view_agenda_outlined,
                title: l10n.sessionNoBlocksTitle,
                message: l10n.sessionNoBlocksBody,
                actionLabel: l10n.sessionAddBlock,
                onAction: () => _addBlock(context),
              ),
            SessionEditorData(:final session, :final exercisesById) =>
              _BlockList(session: session, exercisesById: exercisesById),
          },
        ),
      ),
    );
  }
}

class _BlockList extends StatelessWidget {
  const _BlockList({required this.session, required this.exercisesById});

  final SessionTemplate session;
  final Map<String, Exercise> exercisesById;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.xs,
        AppSpacing.gutter,
        // Clears the extended FAB.
        AppSpacing.xxl * 2,
      ),
      children: [
        for (final (index, block) in session.blocks.indexed) ...[
          _BlockCard(
            block: block,
            exercisesById: exercisesById,
            index: index,
            canMoveUp: index > 0,
            canMoveDown: index < session.blocks.length - 1,
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}

class _BlockCard extends StatelessWidget {
  const _BlockCard({
    required this.block,
    required this.exercisesById,
    required this.index,
    required this.canMoveUp,
    required this.canMoveDown,
  });

  final BlockTemplate block;
  final Map<String, Exercise> exercisesById;

  /// Rendered position, not `block.orderIndex` — soft-deleted siblings keep
  /// their index reserved, so the two diverge.
  final int index;

  final bool canMoveUp;
  final bool canMoveDown;

  Future<void> _edit(BuildContext context) async {
    final cubit = context.read<SessionEditorCubit>();

    final result = await AppSheet.show<BlockFormResult>(
      context,
      builder: (_) => BlockFormSheet(block: block),
    );
    if (result == null || !context.mounted) return;

    final failure = await cubit.updateBlock(
      BlockTemplate(
        id: block.id,
        sessionTemplateId: block.sessionTemplateId,
        kind: result.kind,
        title: result.title,
        orderIndex: block.orderIndex,
        targetMinutes: block.targetMinutes,
        notes: block.notes,
      ),
    );
    if (failure != null && context.mounted) {
      context.showSnackBar(context.l10n.stateErrorBody, isError: true);
    }
  }

  Future<void> _delete(BuildContext context) async {
    final cubit = context.read<SessionEditorCubit>();
    final l10n = context.l10n;

    final confirmed = await confirm(
      context,
      title: l10n.blockDeleteTitle,
      message: l10n.blockDeleteBody,
      confirmLabel: l10n.commonDelete,
    );
    if (!confirmed) return;

    final failure = await cubit.deleteBlock(block.id);
    if (failure != null && context.mounted) {
      context.showSnackBar(l10n.stateErrorBody, isError: true);
    }
  }

  Future<void> _addExercise(BuildContext context) async {
    final cubit = context.read<SessionEditorCubit>();

    final exercise = await AppSheet.show<Exercise>(
      context,
      builder: (_) => const ExercisePickerSheet(),
    );
    if (exercise == null || !context.mounted) return;

    final name = exerciseDisplayName(
      l10n: context.l10n,
      nameKey: exercise.nameKey,
      customName: exercise.customName,
    );

    final prescription = await AppSheet.show<SlotFormResult>(
      context,
      builder: (_) => SlotFormSheet(exerciseName: name),
    );
    if (prescription == null || !context.mounted) return;

    final failure = await cubit.addExercise(
      blockTemplateId: block.id,
      exerciseId: exercise.id,
      targetSets: prescription.targetSets,
      targetRepsMin: prescription.targetRepsMin,
      targetRepsMax: prescription.targetRepsMax,
      restSeconds: prescription.restSeconds,
      perSide: prescription.perSide,
      progression: prescription.progression,
    );
    if (failure != null && context.mounted) {
      context.showSnackBar(context.l10n.stateErrorBody, isError: true);
    }
  }

  void _move(BuildContext context, {required bool up}) {
    getIt<AppHaptics>().selection();
    context.read<SessionEditorCubit>().reorderBlocks(
      index,
      up ? index - 1 : index + 2,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.xs,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(block.title, style: context.textStyles.titleMedium),
                    Text(
                      block.kind.label(l10n),
                      style: context.textStyles.bodySmall?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<void>(
                icon: const Icon(Icons.more_vert_rounded, size: 20),
                itemBuilder: (context) => [
                  PopupMenuItem<void>(
                    onTap: () => _edit(context),
                    child: Text(l10n.commonEdit),
                  ),
                  if (canMoveUp)
                    PopupMenuItem<void>(
                      onTap: () => _move(context, up: true),
                      child: Text(l10n.commonMoveUp),
                    ),
                  if (canMoveDown)
                    PopupMenuItem<void>(
                      onTap: () => _move(context, up: false),
                      child: Text(l10n.commonMoveDown),
                    ),
                  PopupMenuItem<void>(
                    onTap: () => _delete(context),
                    child: Text(
                      l10n.commonDelete,
                      style: TextStyle(color: context.colors.error),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          if (block.exercises.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Text(
                l10n.blockNoExercises,
                style: context.textStyles.bodyMedium?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            )
          else
            _SlotList(block: block, exercisesById: exercisesById),
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xs),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => _addExercise(context),
                icon: const Icon(Icons.add_rounded, size: 20),
                label: Text(l10n.blockAddExercise),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SlotList extends StatelessWidget {
  const _SlotList({required this.block, required this.exercisesById});

  final BlockTemplate block;
  final Map<String, Exercise> exercisesById;

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: block.exercises.length,
      onReorder: (oldIndex, newIndex) {
        getIt<AppHaptics>().selection();
        context.read<SessionEditorCubit>().reorderExercises(
          block,
          oldIndex,
          newIndex,
        );
      },
      itemBuilder: (context, index) {
        final slot = block.exercises[index];
        return _SlotRow(
          key: ValueKey(slot.id),
          slot: slot,
          exercise: exercisesById[slot.exerciseId],
          index: index,
        );
      },
    );
  }
}

class _SlotRow extends StatelessWidget {
  const _SlotRow({
    super.key,
    required this.slot,
    required this.exercise,
    required this.index,
  });

  final ExerciseTemplate slot;

  /// Null only if the catalog row was purged — the prescription still renders,
  /// because a nameless row is better than a crash mid-build.
  final Exercise? exercise;

  final int index;

  String _name(BuildContext context) {
    final catalogEntry = exercise;
    if (catalogEntry == null) return '—';

    return exerciseDisplayName(
      l10n: context.l10n,
      nameKey: catalogEntry.nameKey,
      customName: catalogEntry.customName,
    );
  }

  Future<void> _edit(BuildContext context) async {
    final cubit = context.read<SessionEditorCubit>();

    final result = await AppSheet.show<SlotFormResult>(
      context,
      builder: (_) => SlotFormSheet(
        exerciseName: _name(context),
        slot: slot,
        onRequestDelete: () => _delete(context),
      ),
    );
    if (result == null || !context.mounted) return;

    final failure = await cubit.updateExercise(
      ExerciseTemplate(
        id: slot.id,
        blockTemplateId: slot.blockTemplateId,
        exerciseId: slot.exerciseId,
        orderIndex: slot.orderIndex,
        targetSets: result.targetSets,
        targetRepsMin: result.targetRepsMin,
        targetRepsMax: result.targetRepsMax,
        targetLoadKg: slot.targetLoadKg,
        targetLoadText: slot.targetLoadText,
        targetRpe: slot.targetRpe,
        restSeconds: result.restSeconds,
        perSide: result.perSide,
        tempo: slot.tempo,
        progression: result.progression,
        notes: slot.notes,
      ),
    );
    if (failure != null && context.mounted) {
      context.showSnackBar(context.l10n.stateErrorBody, isError: true);
    }
  }

  Future<void> _delete(BuildContext context) async {
    final cubit = context.read<SessionEditorCubit>();
    final l10n = context.l10n;

    final confirmed = await confirm(
      context,
      title: l10n.slotDeleteTitle,
      message: l10n.slotDeleteBody,
      confirmLabel: l10n.commonDelete,
    );
    if (!confirmed) return;

    final failure = await cubit.deleteExercise(slot.id);
    if (failure != null && context.mounted) {
      context.showSnackBar(l10n.stateErrorBody, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final formatters = Formatters.of(context);

    final reps = switch ((slot.targetRepsMin, slot.targetRepsMax)) {
      (final min?, final max?) when min != max => l10n.slotRepRange(min, max),
      (final min?, _) => '$min',
      (_, final max?) => '$max',
      _ => null,
    };

    final prescription = reps == null
        ? l10n.slotSetsOnly(slot.targetSets)
        : l10n.slotSetsByReps(slot.targetSets, reps);

    final progression = slot.progression.detail(
      l10n,
      formatDecimal: formatters.decimal,
      formatPercent: formatters.percent,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
      child: Material(
        color: context.colors.surfaceContainerHigh,
        borderRadius: AppRadius.mdAll,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _edit(context),
          onLongPress: () => _delete(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _name(context),
                        style: context.textStyles.bodyLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Wrap(
                        spacing: AppSpacing.xs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            prescription,
                            style: context.textStyles.labelLarge?.copyWith(
                              color: context.colors.primary,
                            ),
                          ),
                          Text(
                            l10n.slotRestSeconds(slot.restSeconds),
                            style: context.textStyles.bodySmall?.copyWith(
                              color: context.colors.onSurfaceVariant,
                            ),
                          ),
                          if (slot.perSide)
                            Text(
                              l10n.slotPerSideBadge,
                              style: context.textStyles.bodySmall?.copyWith(
                                color: context.colors.onSurfaceVariant,
                              ),
                            ),
                          if (progression case final detail?)
                            Text(
                              detail,
                              style: context.textStyles.bodySmall?.copyWith(
                                color: context.semanticColors.success,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                ReorderableDragStartListener(
                  index: index,
                  child: Semantics(
                    label: l10n.commonReorderHandle,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.xs),
                      child: Icon(
                        Icons.drag_handle_rounded,
                        size: 20,
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
