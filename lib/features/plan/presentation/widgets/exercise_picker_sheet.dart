import 'package:flutter/material.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/utils/extensions/context_extensions.dart';
import '../../../../domain/entities/exercise.dart';
import '../../../../domain/enums/training_enums.dart';
import '../../../../domain/repositories/exercise_repository.dart';
import '../../../../l10n/generated/app_localizations.dart';
import '../../../../shared/l10n/exercise_name.dart';
import '../../../../shared/widgets/app_sheet.dart';
import '../../../../shared/widgets/state_views.dart';
import 'exercise_form_sheet.dart';
import 'plan_labels.dart';

/// Picks an exercise from the catalog, grouped by body section.
///
/// **Filtering happens in Dart, not SQL.** A seeded exercise's name is an ARB
/// key, so only the presentation layer can resolve it for the active locale —
/// a `LIKE` in the database would match nothing a user actually typed. The
/// catalog is ~120 rows held in memory, so this is a trivial scan.
///
/// Grouping is by [BodySection] rather than [MovementPattern]: someone hunting
/// for an incline press looks under Chest, not under Push. The pattern is
/// still stored, and still what Insights balances volume across.
class ExercisePickerSheet extends StatefulWidget {
  const ExercisePickerSheet({super.key});

  @override
  State<ExercisePickerSheet> createState() => _ExercisePickerSheetState();
}

class _ExercisePickerSheetState extends State<ExercisePickerSheet> {
  final _search = TextEditingController();
  final _repository = getIt<ExerciseRepository>();

  String _query = '';

  @override
  void initState() {
    super.initState();
    _search.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _search
      ..removeListener(_onQueryChanged)
      ..dispose();
    super.dispose();
  }

  void _onQueryChanged() => setState(() => _query = _search.text.trim());

  /// Names already taken, resolved for the active locale.
  ///
  /// System names live in ARB and custom names live in SQLite, so neither the
  /// database nor the repository can see both. This is the only layer that
  /// can, which is why the duplicate check for *seeded* names happens here.
  Set<String> _takenNames(
    List<Exercise> catalog,
    L10n l10n, {
    String? excludingId,
  }) {
    return {
      for (final exercise in catalog)
        if (exercise.id != excludingId)
          exerciseDisplayName(
            l10n: l10n,
            nameKey: exercise.nameKey,
            customName: exercise.customName,
          ).trim().toLowerCase(),
    };
  }

  Future<void> _create(List<Exercise> catalog, {String? seedName}) async {
    final l10n = context.l10n;
    String? error;
    var name = seedName;
    var section = BodySection.fullBody;

    // Loops so a rejected name reopens the sheet with the reason attached,
    // instead of closing and losing what was typed.
    while (true) {
      final result = await AppSheet.show<ExerciseFormResult>(
        context,
        builder: (_) => ExerciseFormSheet(
          title: l10n.pickerCreateTitle,
          initialName: name,
          initialSection: section,
          errorText: error,
        ),
      );
      if (result == null || !mounted) return;

      name = result.name;
      section = result.bodySection;

      if (_takenNames(catalog, l10n).contains(name.trim().toLowerCase())) {
        error = l10n.pickerDuplicateName;
        continue;
      }

      final created = await _repository.createCustom(
        name: name,
        // A user-created exercise has to carry a pattern for the volume
        // charts; the section they chose is the better signal than a fixed
        // default, and both stay editable.
        pattern: _patternFor(section),
        bodySection: section,
        loadType: LoadType.barbell,
      );
      if (!mounted) return;

      switch (created.dataOrNull) {
        case final exercise?:
          Navigator.of(context).pop(exercise);
          return;
        case null:
          error = created.failureOrNull is ParseFailure
              ? l10n.pickerDuplicateName
              : l10n.stateErrorBody;
      }
    }
  }

  Future<void> _rename(Exercise exercise, List<Exercise> catalog) async {
    final l10n = context.l10n;
    String? error;
    var name = exercise.customName;
    var section = exercise.bodySection;

    while (true) {
      final result = await AppSheet.show<ExerciseFormResult>(
        context,
        builder: (_) => ExerciseFormSheet(
          title: l10n.pickerRenameTitle,
          initialName: name,
          initialSection: section,
          errorText: error,
        ),
      );
      if (result == null || !mounted) return;

      name = result.name;
      section = result.bodySection;

      if (_takenNames(
        catalog,
        l10n,
        excludingId: exercise.id,
      ).contains(name.trim().toLowerCase())) {
        error = l10n.pickerDuplicateName;
        continue;
      }

      final renamed = await _repository.renameCustom(
        id: exercise.id,
        name: name,
        bodySection: section,
      );
      if (!mounted) return;

      if (renamed.failureOrNull == null) return;
      error = renamed.failureOrNull is ParseFailure
          ? l10n.pickerDuplicateName
          : l10n.stateErrorBody;
    }
  }

  /// The volume-balance axis for a user-created exercise, inferred from the
  /// section they filed it under. A rough guess beats asking for a second
  /// taxonomy at creation time; it is editable later.
  MovementPattern _patternFor(BodySection section) => switch (section) {
    BodySection.chest || BodySection.shoulders => MovementPattern.push,
    BodySection.upperBack || BodySection.arms => MovementPattern.pull,
    BodySection.lowerBack || BodySection.glutes => MovementPattern.hinge,
    BodySection.legs => MovementPattern.squat,
    BodySection.core => MovementPattern.core,
    BodySection.cardio => MovementPattern.conditioning,
    BodySection.mobility => MovementPattern.mobility,
    BodySection.fullBody => MovementPattern.carry,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.gutter,
                0,
                AppSpacing.gutter,
                AppSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      l10n.pickerTitle,
                      style: context.textStyles.titleLarge,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _search,
                    autofocus: true,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: l10n.pickerSearchHint,
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close_rounded),
                              onPressed: _search.clear,
                              tooltip: l10n.commonCancel,
                            ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<List<Exercise>>(
                stream: _repository.watchCatalog(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return ErrorView(
                      failure: Failure.fromException(snapshot.error!),
                    );
                  }
                  final exercises = snapshot.data;
                  if (exercises == null) {
                    return const LoadingView();
                  }

                  final grouped = _group(exercises, l10n);
                  if (grouped.isEmpty) {
                    return EmptyView(
                      icon: Icons.search_off_rounded,
                      title: l10n.pickerNoResultsTitle,
                      message: l10n.pickerNoResultsBody,
                      actionLabel: _query.isEmpty
                          ? null
                          : l10n.pickerCreateNamed(_query),
                      onAction: _query.isEmpty
                          ? null
                          : () => _create(exercises, seedName: _query),
                    );
                  }

                  return ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
                    // One extra row for "add your own", which stays reachable
                    // when a search *does* match — "Bench press" existing is
                    // no reason you can't add "Bench press (Smith)".
                    itemCount: grouped.length + 1,
                    itemBuilder: (context, index) {
                      if (index == grouped.length) {
                        return _CreateRow(
                          label: _query.isEmpty
                              ? l10n.pickerCreateTitle
                              : l10n.pickerCreateNamed(_query),
                          onTap: () => _create(
                            exercises,
                            seedName: _query.isEmpty ? null : _query,
                          ),
                        );
                      }

                      return grouped[index].build(
                        context,
                        onPick: (exercise) =>
                            Navigator.of(context).pop(exercise),
                        onRename: (exercise) => _rename(exercise, exercises),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Filtered, then grouped by body section, then flattened into rows so the
  /// list can be built lazily rather than as one giant Column.
  List<_PickerRow> _group(List<Exercise> exercises, L10n l10n) {
    final matches = exercises.where((exercise) {
      if (_query.isEmpty) return true;

      final needle = _query.toLowerCase();
      final name = exerciseDisplayName(
        l10n: l10n,
        nameKey: exercise.nameKey,
        customName: exercise.customName,
      ).toLowerCase();

      return name.contains(needle) ||
          exercise.aliases.any((a) => a.toLowerCase().contains(needle));
    }).toList();

    final rows = <_PickerRow>[];
    for (final section in BodySection.values) {
      final inSection = matches
          .where((exercise) => exercise.bodySection == section)
          .toList();
      if (inSection.isEmpty) continue;

      rows.add(_PickerHeader(section));
      rows.addAll(inSection.map(_PickerExercise.new));
    }
    return rows;
  }
}

sealed class _PickerRow {
  const _PickerRow();

  Widget build(
    BuildContext context, {
    required ValueChanged<Exercise> onPick,
    required ValueChanged<Exercise> onRename,
  });
}

class _PickerHeader extends _PickerRow {
  const _PickerHeader(this.section);

  final BodySection section;

  @override
  Widget build(
    BuildContext context, {
    required ValueChanged<Exercise> onPick,
    required ValueChanged<Exercise> onRename,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.md,
        AppSpacing.gutter,
        AppSpacing.xxs,
      ),
      child: Text(
        section.label(context.l10n).toUpperCase(),
        style: context.textStyles.labelSmall?.copyWith(
          color: context.colors.onSurfaceVariant,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PickerExercise extends _PickerRow {
  const _PickerExercise(this.exercise);

  final Exercise exercise;

  @override
  Widget build(
    BuildContext context, {
    required ValueChanged<Exercise> onPick,
    required ValueChanged<Exercise> onRename,
  }) {
    final name = exerciseDisplayName(
      l10n: context.l10n,
      nameKey: exercise.nameKey,
      customName: exercise.customName,
    );

    return ListTile(
      title: Text(name),
      // Only a user's own row can be renamed: a seeded name is an ARB key
      // that every locale resolves, and renaming it here would relabel the
      // same movement across everyone's history (ADR §12.4).
      trailing: exercise.isEditable
          ? IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: context.l10n.pickerRenameTitle,
              onPressed: () => onRename(exercise),
            )
          : null,
      onTap: () => onPick(exercise),
    );
  }
}

class _CreateRow extends StatelessWidget {
  const _CreateRow({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: ListTile(
        leading: Icon(
          Icons.add_circle_outline_rounded,
          color: context.colors.primary,
        ),
        title: Text(
          label,
          style: context.textStyles.bodyLarge?.copyWith(
            color: context.colors.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
        onTap: onTap,
      ),
    );
  }
}
