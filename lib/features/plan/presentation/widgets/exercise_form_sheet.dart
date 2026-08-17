import 'package:flutter/material.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/utils/extensions/context_extensions.dart';
import '../../../../domain/enums/training_enums.dart';
import '../../../../shared/widgets/app_sheet.dart';
import 'plan_labels.dart';

typedef ExerciseFormResult = ({String name, BodySection bodySection});

/// Names and files a user-created exercise — used both to add one and to
/// rename an existing one.
///
/// Uniqueness is not decided here. The sheet reports what was typed; the
/// caller checks it against the catalog and pushes an error back through
/// [errorText], because only the caller can see both the user's own rows and
/// the seeded names that resolve through ARB.
class ExerciseFormSheet extends StatefulWidget {
  const ExerciseFormSheet({
    super.key,
    required this.title,
    this.initialName,
    this.initialSection,
    this.errorText,
  });

  final String title;
  final String? initialName;
  final BodySection? initialSection;

  /// Set by the caller after a rejected save, so the sheet can reopen with the
  /// reason attached to the field rather than as a transient snackbar.
  final String? errorText;

  @override
  State<ExerciseFormSheet> createState() => _ExerciseFormSheetState();
}

class _ExerciseFormSheetState extends State<ExerciseFormSheet> {
  late final _name = TextEditingController(text: widget.initialName);
  late BodySection _section = widget.initialSection ?? BodySection.fullBody;

  /// Cleared as soon as the user edits, so a stale "already exists" doesn't
  /// sit under a name they have since changed.
  late String? _error = widget.errorText;

  @override
  void initState() {
    super.initState();
    _name.addListener(_onNameChanged);
  }

  @override
  void dispose() {
    _name
      ..removeListener(_onNameChanged)
      ..dispose();
    super.dispose();
  }

  void _onNameChanged() {
    if (_error != null) setState(() => _error = null);
    // Keeps the action button's enabled state in step with an empty field.
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final canSave = _name.text.trim().isNotEmpty;

    return AppSheet(
      title: widget.title,
      actionLabel: l10n.commonSave,
      onAction: canSave
          ? () => Navigator.of(
              context,
            ).pop((name: _name.text.trim(), bodySection: _section))
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: l10n.pickerNameLabel,
              errorText: _error,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            l10n.pickerSectionLabel,
            style: context.textStyles.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final section in BodySection.values)
                ChoiceChip(
                  label: Text(section.label(l10n)),
                  selected: _section == section,
                  onSelected: (_) => setState(() => _section = section),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
