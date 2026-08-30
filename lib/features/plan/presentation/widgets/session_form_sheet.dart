import 'package:flutter/material.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/utils/extensions/context_extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../domain/entities/plan.dart';
import '../../../../shared/widgets/app_sheet.dart';

typedef SessionFormResult = ({String code, String title, int? dayOfWeek});

/// Create or edit a session template — "Day A · Push + Core".
class SessionFormSheet extends StatefulWidget {
  const SessionFormSheet({super.key, this.session, this.suggestedCode = 'A'});

  final SessionTemplate? session;

  /// Next unused letter in the phase, so adding days needs no typing beyond
  /// the title.
  final String suggestedCode;

  @override
  State<SessionFormSheet> createState() => _SessionFormSheetState();
}

class _SessionFormSheetState extends State<SessionFormSheet> {
  late final TextEditingController _code = TextEditingController(
    text: widget.session?.code ?? widget.suggestedCode,
  );
  late final TextEditingController _title = TextEditingController(
    text: widget.session?.title ?? '',
  );
  late int? _dayOfWeek = widget.session?.dayOfWeek;

  @override
  void initState() {
    super.initState();
    _code.addListener(_onChanged);
    _title.addListener(_onChanged);
  }

  @override
  void dispose() {
    _code
      ..removeListener(_onChanged)
      ..dispose();
    _title
      ..removeListener(_onChanged)
      ..dispose();
    super.dispose();
  }

  void _onChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isEditing = widget.session != null;
    final isValid =
        _code.text.trim().isNotEmpty && _title.text.trim().isNotEmpty;

    return AppSheet(
      title: isEditing ? l10n.sessionEditTitle : l10n.sessionCreateTitle,
      actionLabel: isEditing ? l10n.commonSave : l10n.commonCreate,
      onAction: isValid
          ? () => Navigator.of(context).pop((
              code: _code.text.trim(),
              title: _title.text.trim(),
              dayOfWeek: _dayOfWeek,
            ))
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 88,
                child: TextField(
                  controller: _code,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 3,
                  decoration: InputDecoration(
                    labelText: l10n.sessionCodeLabel,
                    hintText: l10n.sessionCodeHint,
                    counterText: '',
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: TextField(
                  controller: _title,
                  autofocus: !isEditing,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: l10n.sessionTitleLabel,
                    hintText: l10n.sessionTitleHint,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            l10n.sessionWeekdayLabel,
            style: context.textStyles.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          _WeekdayPicker(
            value: _dayOfWeek,
            onChanged: (day) => setState(() => _dayOfWeek = day),
          ),
        ],
      ),
    );
  }
}

/// Seven chips plus "any day". Weekday names come from `intl`, so they follow
/// the active locale rather than a hardcoded English list.
class _WeekdayPicker extends StatelessWidget {
  const _WeekdayPicker({required this.value, required this.onChanged});

  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final formatters = Formatters.of(context);

    // Any Monday works as an anchor; only the weekday is read off it.
    final anchor = DateTime(2026, 8, 17);

    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        ChoiceChip(
          label: Text(l10n.sessionWeekdayUnset),
          selected: value == null,
          onSelected: (_) => onChanged(null),
        ),
        for (
          var weekday = DateTime.monday;
          weekday <= DateTime.sunday;
          weekday++
        )
          ChoiceChip(
            label: Text(
              formatters.shortWeekday(anchor.add(Duration(days: weekday - 1))),
            ),
            selected: value == weekday,
            onSelected: (_) => onChanged(weekday),
          ),
      ],
    );
  }
}
