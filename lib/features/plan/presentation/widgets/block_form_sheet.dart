import 'package:flutter/material.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/utils/extensions/context_extensions.dart';
import '../../../../domain/entities/plan.dart';
import '../../../../domain/enums/training_enums.dart';
import '../../../../shared/widgets/app_sheet.dart';
import 'plan_labels.dart';

typedef BlockFormResult = ({BlockKind kind, String title});

/// Create or edit a block — the section a group of exercises sits in.
class BlockFormSheet extends StatefulWidget {
  const BlockFormSheet({super.key, this.block});

  final BlockTemplate? block;

  @override
  State<BlockFormSheet> createState() => _BlockFormSheetState();
}

class _BlockFormSheetState extends State<BlockFormSheet> {
  late BlockKind _kind = widget.block?.kind ?? BlockKind.main;
  late final TextEditingController _title = TextEditingController(
    text: widget.block?.title ?? '',
  );

  /// True until the user types their own title, so picking a kind keeps the
  /// title in step — and stops doing that the moment they take over.
  late bool _titleFollowsKind = widget.block == null;

  @override
  void initState() {
    super.initState();
    if (_titleFollowsKind) {
      // Deferred: the kind's label needs a BuildContext with localizations,
      // which initState doesn't have.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _title.text.isEmpty) {
          _title.text = _kind.label(context.l10n);
        }
      });
    }
    _title.addListener(_onTitleChanged);
  }

  @override
  void dispose() {
    _title
      ..removeListener(_onTitleChanged)
      ..dispose();
    super.dispose();
  }

  void _onTitleChanged() => setState(() {});

  void _selectKind(BlockKind kind) {
    setState(() {
      _kind = kind;
      if (_titleFollowsKind) _title.text = kind.label(context.l10n);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isEditing = widget.block != null;
    final isValid = _title.text.trim().isNotEmpty;

    return AppSheet(
      title: isEditing ? l10n.blockEditTitle : l10n.blockCreateTitle,
      actionLabel: isEditing ? l10n.commonSave : l10n.commonCreate,
      onAction: isValid
          ? () => Navigator.of(
              context,
            ).pop((kind: _kind, title: _title.text.trim()))
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.blockKindLabel,
            style: context.textStyles.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final kind in BlockKind.values)
                ChoiceChip(
                  label: Text(kind.label(l10n)),
                  selected: _kind == kind,
                  onSelected: (_) => _selectKind(kind),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => _titleFollowsKind = false,
            decoration: InputDecoration(labelText: l10n.blockTitleLabel),
          ),
        ],
      ),
    );
  }
}
