import 'package:flutter/material.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/utils/extensions/context_extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../domain/entities/exercise.dart';
import '../../../../domain/entities/plan.dart';
import '../../../../domain/entities/session_log.dart';
import '../../../../domain/services/metrics_service.dart';
import '../../../../shared/widgets/app_sheet.dart';
import '../widgets/rpe_dots.dart';

typedef FinalizeResult = ({double? sessionRpe, int? energy, String? notes});

/// One sheet at the end of a session: how hard, how you felt, and anything
/// worth remembering (ADR §9.3).
///
/// Everything on it is optional. A session that took ninety minutes should not
/// be gated behind three more taps, so the confirm button is always live.
class FinalizeSheet extends StatefulWidget {
  const FinalizeSheet({super.key});

  @override
  State<FinalizeSheet> createState() => _FinalizeSheetState();
}

class _FinalizeSheetState extends State<FinalizeSheet> {
  final _notes = TextEditingController();
  double? _rpe;
  int? _energy;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return AppSheet(
      title: l10n.finalizeTitle,
      actionLabel: l10n.finalizeConfirm,
      onAction: () => Navigator.of(context).pop((
        sessionRpe: _rpe,
        energy: _energy,
        notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      )),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.finalizeEffortLabel,
            style: context.textStyles.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          RpeDots(
            value: _rpe,
            onChanged: (value) => setState(() => _rpe = value),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            l10n.finalizeEnergyLabel,
            style: context.textStyles.bodySmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
          EnergyFaces(
            value: _energy,
            onChanged: (value) => setState(() => _energy = value),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _notes,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: l10n.finalizeNoteLabel,
              hintText: l10n.finalizeNoteHint,
            ),
          ),
        ],
      ),
    );
  }
}

/// What the session amounted to, shown once on the way out (ADR §9.3).
class SessionSummarySheet extends StatelessWidget {
  const SessionSummarySheet({
    super.key,
    required this.log,
    required this.template,
    required this.exercisesById,
  });

  final SessionLog log;
  final SessionTemplate? template;
  final Map<String, Exercise> exercisesById;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final formatters = Formatters.of(context);

    final summary = MetricsService.summarize(
      log: log,
      template: template,
      exercisesById: exercisesById,
    );

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.gutter,
          0,
          AppSpacing.gutter,
          AppSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                l10n.summaryTitle,
                style: context.textStyles.titleLarge,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                _Stat(
                  label: l10n.summarySets(summary.completedSets),
                  emphasised: true,
                ),
                _Stat(label: l10n.summaryDuration(summary.duration.inMinutes)),
                if (summary.tonnageKg > 0)
                  _Stat(
                    label: l10n.summaryTonnage(
                      formatters.decimal(summary.tonnageKg, fractionDigits: 0),
                    ),
                  ),
                if (summary.adherence case final adherence?)
                  _Stat(
                    label: l10n.summaryAdherence(formatters.percent(adherence)),
                  ),
                if (summary.skippedSets > 0)
                  _Stat(label: l10n.summarySkipped(summary.skippedSets)),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.summaryDone),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, this.emphasised = false});

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
          vertical: AppSpacing.xs,
        ),
        child: Text(
          label,
          style: context.textStyles.labelLarge?.copyWith(
            color: emphasised
                ? context.colors.onPrimaryContainer
                : context.colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
