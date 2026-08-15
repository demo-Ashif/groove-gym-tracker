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
import '../../../../shared/widgets/state_views.dart';
import 'plan_labels.dart';

/// Picks an exercise from the catalog, grouped by movement pattern.
///
/// **Filtering happens in Dart, not SQL.** A seeded exercise's name is an ARB
/// key, so only the presentation layer can resolve it for the active locale —
/// a `LIKE` in the database would match nothing a user actually typed. The
/// catalog is ~120 rows held in memory, so this is a trivial scan.
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

  Future<void> _createAndPick(String name) async {
    final result = await _repository.createCustom(
      name: name,
      // A user-created exercise has to be filed somewhere; "main" work with a
      // barbell is the least surprising default, and both are editable later.
      pattern: MovementPattern.push,
      loadType: LoadType.barbell,
    );

    if (!mounted) return;

    switch (result.dataOrNull) {
      case final exercise?:
        Navigator.of(context).pop(exercise);
      case null:
        context.showSnackBar(context.l10n.stateErrorBody, isError: true);
    }
  }

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
                          : () => _createAndPick(_query),
                    );
                  }

                  return ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
                    itemCount: grouped.length,
                    itemBuilder: (context, index) => grouped[index].build(
                      context,
                      onPick: (exercise) => Navigator.of(context).pop(exercise),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Filtered, then grouped by pattern, then flattened into rows so the list
  /// can be built lazily rather than as one giant Column.
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
    for (final pattern in MovementPattern.values) {
      final inPattern = matches
          .where((exercise) => exercise.pattern == pattern)
          .toList();
      if (inPattern.isEmpty) continue;

      rows.add(_PickerHeader(pattern));
      rows.addAll(inPattern.map(_PickerExercise.new));
    }
    return rows;
  }
}

sealed class _PickerRow {
  const _PickerRow();

  Widget build(BuildContext context, {required ValueChanged<Exercise> onPick});
}

class _PickerHeader extends _PickerRow {
  const _PickerHeader(this.pattern);

  final MovementPattern pattern;

  @override
  Widget build(BuildContext context, {required ValueChanged<Exercise> onPick}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.md,
        AppSpacing.gutter,
        AppSpacing.xxs,
      ),
      child: Text(
        pattern.label(context.l10n).toUpperCase(),
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
  Widget build(BuildContext context, {required ValueChanged<Exercise> onPick}) {
    final name = exerciseDisplayName(
      l10n: context.l10n,
      nameKey: exercise.nameKey,
      customName: exercise.customName,
    );

    return ListTile(
      title: Text(name),
      // A custom exercise is worth marking: it is the user's own row, and the
      // only kind they can edit.
      trailing: exercise.isSystem
          ? null
          : Icon(
              Icons.person_outline_rounded,
              size: 18,
              color: context.colors.onSurfaceVariant,
            ),
      onTap: () => onPick(exercise),
    );
  }
}
