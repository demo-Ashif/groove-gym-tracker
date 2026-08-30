import 'package:flutter/material.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/utils/extensions/context_extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../domain/enums/training_enums.dart';
import '../../../../domain/values/schedule_pattern.dart';
import '../../../../l10n/generated/app_localizations.dart';

/// The seven-chip week (ADR §8.1): tap a day, say what happens on it.
///
/// **The week starts where the locale says it starts.** Sunday-first,
/// Monday-first and Saturday-first are all real, and
/// `MaterialLocalizations.firstDayOfWeekIndex` is the only correct source for
/// it — hardcoding one would silently mis-order the strip for most of the world
/// (ADR §12.2 rule 8).
class WeekStrip extends StatelessWidget {
  const WeekStrip({
    super.key,
    required this.pattern,
    required this.onDayTapped,
  });

  final WeeklyPattern pattern;

  /// Receives an ISO-8601 weekday, 1 = Monday … 7 = Sunday.
  final ValueChanged<int> onDayTapped;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final formatters = Formatters.of(context);

    // `firstDayOfWeekIndex` is 0 = Sunday … 6 = Saturday; the schema and
    // `DateTime` are 1 = Monday … 7 = Sunday. Converting once here keeps that
    // mismatch out of every call site.
    final firstDay = MaterialLocalizations.of(context).firstDayOfWeekIndex;
    final weekdays = List.generate(7, (index) {
      final sundayBased = (firstDay + index) % 7;
      return sundayBased == 0 ? DateTime.sunday : sundayBased;
    });

    // Any Monday; only the weekday is read off it, so `intl` can name the days
    // in the active locale.
    final anchor = DateTime(2026, 8, 17);

    return Row(
      children: [
        for (final weekday in weekdays)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: _DayChip(
                label: formatters.shortWeekday(
                  anchor.add(Duration(days: weekday - 1)),
                ),
                assignment: pattern.days[weekday] ?? const DayAssignment.rest(),
                onTap: () => onDayTapped(weekday),
                l10n: l10n,
              ),
            ),
          ),
      ],
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.label,
    required this.assignment,
    required this.onTap,
    required this.l10n,
  });

  final String label;
  final DayAssignment assignment;
  final VoidCallback onTap;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isGym = assignment.isGym;

    final (background, foreground) = switch (assignment.kind) {
      // The accent marks training days, which is what the strip is read for.
      ScheduledSessionKind.gym => (colors.primary, colors.onPrimary),
      ScheduledSessionKind.cricket => (
        colors.secondaryContainer,
        colors.onSecondaryContainer,
      ),
      ScheduledSessionKind.custom => (
        colors.surfaceContainerHighest,
        colors.onSurface,
      ),
      ScheduledSessionKind.rest => (
        colors.surfaceContainerHigh,
        colors.onSurfaceVariant,
      ),
    };

    return Semantics(
      button: true,
      label: '$label, ${_assignmentLabel()}',
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: AppRadius.mdAll,
            child: AnimatedContainer(
              duration: AppDurations.micro,
              curve: AppMotion.micro,
              // Taller than a plain chip so the assignment fits underneath the
              // weekday, and past the 48dp minimum target either way.
              height: 66,
              decoration: BoxDecoration(
                color: background,
                borderRadius: AppRadius.mdAll,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: context.textStyles.labelSmall?.copyWith(
                      color: foreground.withValues(alpha: 0.75),
                    ),
                    maxLines: 1,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _shortLabel(),
                    style: context.textStyles.labelLarge?.copyWith(
                      color: foreground,
                      fontWeight: isGym ? FontWeight.w700 : FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// One or two characters, because seven of these share a phone's width. The
  /// full wording lives in the semantic label above, so a screen reader still
  /// gets the real thing.
  String _shortLabel() => switch (assignment.kind) {
    ScheduledSessionKind.gym => assignment.sessionCode ?? '—',
    ScheduledSessionKind.cricket => '🏏',
    ScheduledSessionKind.custom => '•',
    ScheduledSessionKind.rest => '—',
  };

  String _assignmentLabel() => switch (assignment.kind) {
    ScheduledSessionKind.gym => l10n.scheduleGymDay(
      assignment.sessionCode ?? '',
    ),
    ScheduledSessionKind.cricket => l10n.scheduleCricket,
    ScheduledSessionKind.custom => l10n.scheduleCustom,
    ScheduledSessionKind.rest => l10n.scheduleRest,
  };
}

/// The sheet behind a chip: rest, cricket, custom, or one of the program's
/// session codes. Zero typing (ADR §8.1).
class DayAssignmentSheet extends StatelessWidget {
  const DayAssignmentSheet({
    super.key,
    required this.weekdayLabel,
    required this.availableCodes,
    required this.current,
  });

  final String weekdayLabel;

  /// Session codes across the whole program, deduplicated — each phase has its
  /// own Day A, and the strip assigns the code, not one phase's template.
  final List<String> availableCodes;

  final DayAssignment current;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

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
                l10n.scheduleAssignTitle(weekdayLabel),
                style: context.textStyles.titleLarge,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            if (availableCodes.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Text(
                  l10n.scheduleNoSessions,
                  style: context.textStyles.bodyMedium?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
              ),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final code in availableCodes)
                  ChoiceChip(
                    label: Text(l10n.scheduleGymDay(code)),
                    selected: current.sessionCode == code,
                    onSelected: (_) =>
                        Navigator.of(context).pop(DayAssignment.gym(code)),
                  ),
                ChoiceChip(
                  label: Text(l10n.scheduleRest),
                  selected: current.kind == ScheduledSessionKind.rest,
                  onSelected: (_) =>
                      Navigator.of(context).pop(const DayAssignment.rest()),
                ),
                ChoiceChip(
                  label: Text(l10n.scheduleCricket),
                  selected: current.kind == ScheduledSessionKind.cricket,
                  onSelected: (_) =>
                      Navigator.of(context).pop(const DayAssignment.cricket()),
                ),
                ChoiceChip(
                  label: Text(l10n.scheduleCustom),
                  selected: current.kind == ScheduledSessionKind.custom,
                  onSelected: (_) =>
                      Navigator.of(context).pop(const DayAssignment.custom()),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              l10n.scheduleMissingNote,
              style: context.textStyles.bodySmall?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
