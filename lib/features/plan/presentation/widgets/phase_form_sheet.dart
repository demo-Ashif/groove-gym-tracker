import 'package:flutter/material.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/utils/extensions/context_extensions.dart';
import '../../../../domain/entities/plan.dart';
import '../../../../shared/widgets/app_sheet.dart';
import '../../../../shared/widgets/stepper_field.dart';

typedef PhaseFormResult = ({String name, int startWeek, int endWeek});

/// Create or edit a phase — a run of program weeks with its own targets.
class PhaseFormSheet extends StatefulWidget {
  const PhaseFormSheet({super.key, this.phase, this.suggestedStartWeek = 1});

  final Phase? phase;

  /// Where the next phase would naturally begin: the week after the last one
  /// ends, so adding phases in order needs no thinking.
  final int suggestedStartWeek;

  @override
  State<PhaseFormSheet> createState() => _PhaseFormSheetState();
}

class _PhaseFormSheetState extends State<PhaseFormSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.phase?.name ?? '',
  );
  late int _startWeek = widget.phase?.startWeek ?? widget.suggestedStartWeek;
  late int _endWeek = widget.phase?.endWeek ?? (_startWeek + 2);

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

  void _onNameChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isEditing = widget.phase != null;
    final isValid = _name.text.trim().isNotEmpty;

    return AppSheet(
      title: isEditing ? l10n.phaseEditTitle : l10n.phaseCreateTitle,
      actionLabel: isEditing ? l10n.commonSave : l10n.commonCreate,
      onAction: isValid
          ? () => Navigator.of(context).pop((
              name: _name.text.trim(),
              startWeek: _startWeek,
              endWeek: _endWeek,
            ))
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _name,
            autofocus: !isEditing,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: l10n.phaseNameLabel,
              hintText: l10n.phaseNameHint,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          // Bound as a range: pushing the start past the end drags the end
          // with it, so an inverted phase can't be built in the first place.
          RangeStepperField(
            minLabel: l10n.phaseStartWeekLabel,
            maxLabel: l10n.phaseEndWeekLabel,
            minValue: _startWeek,
            maxValue: _endWeek,
            lowerBound: 1,
            upperBound: 52,
            onChanged: (start, end) => setState(() {
              _startWeek = start;
              _endWeek = end;
            }),
          ),
        ],
      ),
    );
  }
}
