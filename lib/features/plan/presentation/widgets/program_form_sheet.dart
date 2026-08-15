import 'package:flutter/material.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/utils/extensions/context_extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../domain/values/calendar_date.dart';
import '../../../../shared/widgets/app_sheet.dart';

/// What the create/edit program sheet hands back.
typedef ProgramFormResult = ({String name, CalendarDate startDate});

/// Create or rename a program.
///
/// Pops a [ProgramFormResult], or null if dismissed — the caller decides what
/// to do with it, so the sheet never has to know about a cubit.
class ProgramFormSheet extends StatefulWidget {
  const ProgramFormSheet({super.key, this.initialName, this.initialStartDate});

  final String? initialName;
  final CalendarDate? initialStartDate;

  bool get isEditing => initialName != null;

  @override
  State<ProgramFormSheet> createState() => _ProgramFormSheetState();
}

class _ProgramFormSheetState extends State<ProgramFormSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName ?? '',
  );
  late CalendarDate _startDate =
      widget.initialStartDate ?? CalendarDate.today();

  @override
  void initState() {
    super.initState();
    // Rebuilds so the primary action enables the moment the field is
    // non-empty, rather than staying dead until the user hits Save.
    _name.addListener(_onNameChanged);
  }

  @override
  void dispose() {
    _name
      ..removeListener(_onNameChanged)
      ..dispose();
    super.dispose();
  }

  void _onNameChanged() => setState(() {});

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate.toDateTime(),
      // A program can be backdated a year (logging a block already underway)
      // or planned two years out. Wider than that is a typo, not an intent.
      firstDate: DateTime(DateTime.now().year - 1),
      lastDate: DateTime(DateTime.now().year + 2),
    );
    if (picked == null || !mounted) return;

    setState(() => _startDate = CalendarDate.from(picked));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final formatters = Formatters.of(context);
    final isValid = _name.text.trim().isNotEmpty;

    return AppSheet(
      title: widget.isEditing ? l10n.programEditTitle : l10n.programCreateTitle,
      actionLabel: widget.isEditing ? l10n.commonSave : l10n.commonCreate,
      onAction: isValid
          ? () => Navigator.of(
              context,
            ).pop((name: _name.text.trim(), startDate: _startDate))
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _name,
            autofocus: !widget.isEditing,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: l10n.programNameLabel,
              hintText: l10n.programNameHint,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _DateRow(
            label: l10n.programStartDateLabel,
            value: formatters.longDate(_startDate.toDateTime()),
            onTap: _pickDate,
          ),
        ],
      ),
    );
  }
}

class _DateRow extends StatelessWidget {
  const _DateRow({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.colors.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.lgAll,
        side: BorderSide(color: context.colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: context.textStyles.bodySmall?.copyWith(
                        color: context.colors.onSurfaceVariant,
                      ),
                    ),
                    Text(value, style: context.textStyles.bodyLarge),
                  ],
                ),
              ),
              Icon(
                Icons.calendar_today_rounded,
                size: 20,
                color: context.colors.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
