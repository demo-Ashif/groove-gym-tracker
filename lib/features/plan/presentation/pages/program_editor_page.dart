import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/router/app_routes.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/haptics/app_haptics.dart';
import '../../../../core/utils/extensions/context_extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../domain/entities/plan.dart';
import '../../../../domain/enums/training_enums.dart';
import '../../../../domain/values/schedule_pattern.dart';
import '../../../../shared/widgets/app_card.dart';
import '../../../../core/error/result.dart';
import '../../../../shared/widgets/app_sheet.dart';
import '../../../../shared/widgets/page_header.dart';
import '../../../../shared/widgets/skeleton.dart';
import '../../../../shared/widgets/state_views.dart';
import '../cubit/program_editor_cubit.dart';
import '../cubit/program_editor_state.dart';
import '../widgets/phase_form_sheet.dart';
import '../widgets/program_form_sheet.dart';
import '../widgets/session_form_sheet.dart';
import '../widgets/week_strip.dart';

/// Builds a program: phases, and the training days inside them.
///
/// Phases move with an explicit menu action rather than a drag, and the days
/// inside them drag. That split is deliberate — nesting two reorderable lists
/// inside one scroll is where drag targets start fighting each other, and
/// reordering phases is a once-per-program action while reordering days is
/// routine.
class ProgramEditorPage extends StatelessWidget {
  const ProgramEditorPage({super.key, required this.programId});

  final String programId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<ProgramEditorCubit>(param1: programId),
      child: _ProgramEditorView(programId: programId),
    );
  }
}

class _ProgramEditorView extends StatelessWidget {
  const _ProgramEditorView({required this.programId});

  final String programId;

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ProgramEditorCubit, ProgramEditorState>(
      // Deleting the program you are editing is a normal outcome, not an
      // error — leave rather than sit on rows that no longer exist.
      listenWhen: (_, current) => current is ProgramEditorGone,
      listener: (context, _) {
        if (context.canPop()) context.pop();
      },
      builder: (context, state) => Scaffold(
        appBar: AppBar(
          title: Text(switch (state) {
            ProgramEditorData(:final program) => program.name,
            _ => context.l10n.planTitle,
          }),
          actions: [
            if (state case ProgramEditorData(:final program))
              _ProgramActions(program: program),
          ],
        ),
        body: SafeArea(
          top: false,
          child: switch (state) {
            ProgramEditorLoading() => const Padding(
              padding: EdgeInsets.all(AppSpacing.gutter),
              child: Shimmer(
                child: Column(
                  children: [
                    SkeletonCard(height: 140),
                    SizedBox(height: AppSpacing.sm),
                    SkeletonCard(height: 140),
                  ],
                ),
              ),
            ),
            ProgramEditorFailure(:final failure) => ErrorView(failure: failure),
            // A frame or two while the pop lands.
            ProgramEditorGone() => const SizedBox.shrink(),
            ProgramEditorData(:final program) => _EditorBody(
              program: program,
              programId: programId,
              state: state,
            ),
          },
        ),
      ),
    );
  }
}

class _ProgramActions extends StatelessWidget {
  const _ProgramActions({required this.program});

  final Program program;

  Future<void> _delete(BuildContext context) async {
    final cubit = context.read<ProgramEditorCubit>();
    final l10n = context.l10n;

    final confirmed = await confirm(
      context,
      title: l10n.programDeleteTitle,
      message: l10n.programDeleteBody,
      confirmLabel: l10n.commonDelete,
    );
    if (!confirmed) return;

    // The stream reports the deletion and the page pops itself, so there is
    // nothing to navigate here.
    final failure = await cubit.deleteProgram();
    if (failure != null && context.mounted) {
      context.showSnackBar(l10n.stateErrorBody, isError: true);
    }
  }

  Future<void> _rename(BuildContext context) async {
    final cubit = context.read<ProgramEditorCubit>();

    final result = await AppSheet.show<ProgramFormResult>(
      context,
      builder: (_) => ProgramFormSheet(
        initialName: program.name,
        initialStartDate: program.startDate,
      ),
    );
    if (result == null || !context.mounted) return;

    final failure = await cubit.renameProgram(result.name);
    if (failure != null && context.mounted) {
      context.showSnackBar(context.l10n.stateErrorBody, isError: true);
    }
  }

  Future<void> _setActive(BuildContext context) async {
    final failure = await context.read<ProgramEditorCubit>().setActive();
    if (failure != null && context.mounted) {
      context.showSnackBar(context.l10n.stateErrorBody, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return PopupMenuButton<void>(
      icon: const Icon(Icons.more_vert_rounded),
      itemBuilder: (context) => [
        PopupMenuItem<void>(
          onTap: () => _rename(context),
          child: Text(l10n.commonEdit),
        ),
        if (!program.isActive)
          PopupMenuItem<void>(
            onTap: () => _setActive(context),
            child: Text(l10n.programSetActive),
          ),
        PopupMenuItem<void>(
          onTap: () => _delete(context),
          child: Text(
            l10n.commonDelete,
            style: TextStyle(color: context.colors.error),
          ),
        ),
      ],
    );
  }
}

/// The editor's scroll: schedule first, then the phases it draws from.
class _EditorBody extends StatelessWidget {
  const _EditorBody({
    required this.program,
    required this.programId,
    required this.state,
  });

  final Program program;
  final String programId;
  final ProgramEditorData state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.xs,
        AppSpacing.gutter,
        AppSpacing.xxl,
      ),
      children: [
        if (program.isActive)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Text(
              l10n.programActiveNote,
              style: context.textStyles.bodySmall?.copyWith(
                color: context.colors.primary,
              ),
            ),
          ),
        _ScheduleCard(program: program, state: state),
        SectionLabel(l10n.programPhasesSection),
        if (program.phases.isEmpty)
          _NoPhases(programId: programId, program: program)
        else
          for (final (index, phase) in program.phases.indexed) ...[
            _PhaseCard(
              phase: phase,
              programId: programId,
              index: index,
              canMoveUp: index > 0,
              canMoveDown: index < program.phases.length - 1,
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        const SizedBox(height: AppSpacing.xs),
        OutlinedButton.icon(
          onPressed: () => addPhase(context, program),
          icon: const Icon(Icons.add_rounded),
          label: Text(l10n.programAddPhase),
        ),
      ],
    );
  }
}

class _NoPhases extends StatelessWidget {
  const _NoPhases({required this.programId, required this.program});

  final String programId;
  final Program program;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.programNoPhasesTitle, style: context.textStyles.titleSmall),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            l10n.programNoPhasesBody,
            style: context.textStyles.bodyMedium?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// The week strip, its summary, and the action that turns it into dates.
class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({required this.program, required this.state});

  final Program program;
  final ProgramEditorData state;

  /// Codes across the whole program, deduplicated and ordered — the strip
  /// assigns a code, and every phase resolves it to its own Day A.
  List<String> get _codes {
    final codes = <String>{
      for (final phase in program.phases)
        for (final session in phase.sessions) session.code,
    }.toList();
    codes.sort();
    return codes;
  }

  Future<void> _assign(BuildContext context, int weekday) async {
    final cubit = context.read<ProgramEditorCubit>();
    final formatters = Formatters.of(context);
    final anchor = DateTime(2026, 8, 17).add(Duration(days: weekday - 1));

    final assignment = await showModalBottomSheet<DayAssignment>(
      context: context,
      useSafeArea: true,
      builder: (_) => DayAssignmentSheet(
        weekdayLabel: formatters.longWeekday(anchor),
        availableCodes: _codes,
        current: state.draftPattern.days[weekday] ?? const DayAssignment.rest(),
      ),
    );
    if (assignment == null) return;

    getIt<AppHaptics>().selection();
    cubit.assignDay(weekday, assignment);
  }

  Future<void> _commit(BuildContext context) async {
    final cubit = context.read<ProgramEditorCubit>();
    final l10n = context.l10n;

    final result = await cubit.commitSchedule();
    if (!context.mounted) return;

    switch (result) {
      case Success(:final data):
        getIt<AppHaptics>().light();
        context.showSnackBar(
          data.added == 0 && data.removed == 0
              ? l10n.scheduleUnchanged
              : l10n.scheduleCommitted(data.added),
        );
      case Err():
        context.showSnackBar(l10n.stateErrorBody, isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final days = state.draftPattern.days.values;

    final gym = days.where((d) => d.kind == ScheduledSessionKind.gym).length;
    final cricket = days
        .where((d) => d.kind == ScheduledSessionKind.cricket)
        .length;
    // Absent weekdays are rest days, which is why this counts the gaps rather
    // than the entries.
    final rest =
        7 - days.where((d) => d.kind != ScheduledSessionKind.rest).length;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.scheduleSection,
                  style: context.textStyles.titleMedium,
                ),
              ),
              if (state.hasUncommittedSchedule)
                _UncommittedBadge(label: l10n.scheduleUnsaved),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          WeekStrip(
            pattern: state.draftPattern,
            onDayTapped: (weekday) => _assign(context, weekday),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            l10n.scheduleWeekStripHint,
            style: context.textStyles.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              _SummaryPill(label: l10n.scheduleGymCount(gym)),
              _SummaryPill(label: l10n.scheduleCricketCount(cricket)),
              _SummaryPill(label: l10n.scheduleRestCount(rest)),
              _SummaryPill(
                label: l10n.scheduleDayCount(state.scheduledDayCount),
                emphasised: state.scheduledDayCount > 0,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            // Nothing to schedule against without phases, and the repository
            // would refuse anyway — better to read as disabled than to fail.
            onPressed: program.phases.isEmpty ? null : () => _commit(context),
            icon: const Icon(Icons.event_available_rounded),
            label: Text(
              state.scheduledDayCount == 0
                  ? l10n.scheduleCommit
                  : l10n.scheduleRecommit,
            ),
          ),
        ],
      ),
    );
  }
}

class _UncommittedBadge extends StatelessWidget {
  const _UncommittedBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: semantic.warningContainer,
        borderRadius: AppRadius.fullAll,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: 2,
        ),
        child: Text(
          label,
          style: context.textStyles.labelSmall?.copyWith(
            color: semantic.onWarningContainer,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _SummaryPill extends StatelessWidget {
  const _SummaryPill({required this.label, this.emphasised = false});

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

/// Adds a phase, starting where the last one left off so the user does no
/// arithmetic.
Future<void> addPhase(BuildContext context, Program program) async {
  final cubit = context.read<ProgramEditorCubit>();

  final nextWeek = program.phases.isEmpty
      ? 1
      : program.phases
                .map((phase) => phase.endWeek)
                .reduce((a, b) => a > b ? a : b) +
            1;

  final result = await AppSheet.show<PhaseFormResult>(
    context,
    builder: (_) => PhaseFormSheet(suggestedStartWeek: nextWeek),
  );
  if (result == null || !context.mounted) return;

  final failure = await cubit.addPhase(
    name: result.name,
    startWeek: result.startWeek,
    endWeek: result.endWeek,
  );
  if (failure != null && context.mounted) {
    context.showSnackBar(context.l10n.stateErrorBody, isError: true);
  }
}

class _PhaseCard extends StatelessWidget {
  const _PhaseCard({
    required this.phase,
    required this.programId,
    required this.index,
    required this.canMoveUp,
    required this.canMoveDown,
  });

  final Phase phase;
  final String programId;

  /// Position in the rendered list — **not** `phase.orderIndex`. A soft-deleted
  /// sibling keeps its index reserved, so the two diverge as soon as anything
  /// is deleted.
  final int index;

  final bool canMoveUp;
  final bool canMoveDown;

  Future<void> _edit(BuildContext context) async {
    final cubit = context.read<ProgramEditorCubit>();

    final result = await AppSheet.show<PhaseFormResult>(
      context,
      builder: (_) => PhaseFormSheet(phase: phase),
    );
    if (result == null || !context.mounted) return;

    final failure = await cubit.updatePhase(
      Phase(
        id: phase.id,
        programId: phase.programId,
        name: result.name,
        orderIndex: phase.orderIndex,
        startWeek: result.startWeek,
        endWeek: result.endWeek,
        targetSessionMinutes: phase.targetSessionMinutes,
        rpeLow: phase.rpeLow,
        rpeHigh: phase.rpeHigh,
        checkInDueAtEnd: phase.checkInDueAtEnd,
      ),
    );
    if (failure != null && context.mounted) {
      context.showSnackBar(context.l10n.stateErrorBody, isError: true);
    }
  }

  Future<void> _delete(BuildContext context) async {
    final cubit = context.read<ProgramEditorCubit>();
    final l10n = context.l10n;

    final confirmed = await confirm(
      context,
      title: l10n.phaseDeleteTitle,
      message: l10n.phaseDeleteBody,
      confirmLabel: l10n.commonDelete,
    );
    if (!confirmed) return;

    final failure = await cubit.deletePhase(phase.id);
    if (failure != null && context.mounted) {
      context.showSnackBar(l10n.stateErrorBody, isError: true);
    }
  }

  Future<void> _addSession(BuildContext context) async {
    final cubit = context.read<ProgramEditorCubit>();

    final result = await AppSheet.show<SessionFormResult>(
      context,
      builder: (_) => SessionFormSheet(suggestedCode: _nextCode()),
    );
    if (result == null || !context.mounted) return;

    final failure = await cubit.addSession(
      phaseId: phase.id,
      code: result.code,
      title: result.title,
      dayOfWeek: result.dayOfWeek,
    );
    if (failure != null && context.mounted) {
      context.showSnackBar(context.l10n.stateErrorBody, isError: true);
    }
  }

  /// A, B, C… continuing from whatever the phase already has. Falls back to
  /// the count once past Z, which no plan will reach.
  String _nextCode() {
    final index = phase.sessions.length;
    return index < 26
        ? String.fromCharCode('A'.codeUnitAt(0) + index)
        : '${index + 1}';
  }

  void _move(BuildContext context, {required bool up}) {
    getIt<AppHaptics>().selection();
    // ReorderableListView semantics: a downward move targets the slot the item
    // would land at *before* it is removed, hence +2 rather than +1.
    context.read<ProgramEditorCubit>().reorderPhases(
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
                    Text(phase.name, style: context.textStyles.titleMedium),
                    Text(
                      l10n.phaseWeekRange(phase.startWeek, phase.endWeek),
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
          if (phase.sessions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Text(
                l10n.phaseNoSessions,
                style: context.textStyles.bodyMedium?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            )
          else
            _SessionList(phase: phase, programId: programId),
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xs),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => _addSession(context),
                icon: const Icon(Icons.add_rounded, size: 20),
                label: Text(l10n.phaseAddSession),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SessionList extends StatelessWidget {
  const _SessionList({required this.phase, required this.programId});

  final Phase phase;
  final String programId;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return ReorderableListView.builder(
      // Nested inside the page's scroll view, so it must not scroll itself.
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: phase.sessions.length,
      onReorder: (oldIndex, newIndex) {
        getIt<AppHaptics>().selection();
        context.read<ProgramEditorCubit>().reorderSessions(
          phase,
          oldIndex,
          newIndex,
        );
      },
      itemBuilder: (context, index) {
        final session = phase.sessions[index];

        return Padding(
          key: ValueKey(session.id),
          padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
          child: Material(
            color: context.colors.surfaceContainerHigh,
            borderRadius: AppRadius.mdAll,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () =>
                  context.push(AppRoutes.sessionEditor(programId, session.id)),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                child: Row(
                  children: [
                    _SessionCodeBadge(code: session.code),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            session.title,
                            style: context.textStyles.bodyLarge,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            l10n.sessionSetCount(session.totalSets),
                            style: context.textStyles.bodySmall?.copyWith(
                              color: context.colors.onSurfaceVariant,
                            ),
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
      },
    );
  }
}

class _SessionCodeBadge extends StatelessWidget {
  const _SessionCodeBadge({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.colors.primaryContainer,
        borderRadius: AppRadius.smAll,
      ),
      child: Text(
        code,
        style: context.textStyles.labelLarge?.copyWith(
          color: context.colors.onPrimaryContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
