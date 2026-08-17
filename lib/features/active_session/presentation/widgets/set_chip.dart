import 'package:flutter/material.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/utils/extensions/context_extensions.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../domain/entities/session_log.dart';
import '../../../../domain/enums/training_enums.dart';

/// One set, as a tappable chip.
///
/// The most-repeated interaction in the app, so it gets the most craft
/// (ADR §14.2): confirming a set scales the chip down and back with an
/// overshoot, and the fill sweeps in rather than snapping. Everything else on
/// this screen is calm so that this can be the thing that moves.
class SetChip extends StatelessWidget {
  const SetChip({
    super.key,
    required this.setIndex,
    required this.set,
    required this.isActive,
    required this.onTap,
    required this.onLongPress,
  });

  /// 0-based position within the exercise.
  final int setIndex;

  /// Null when the set hasn't been logged yet.
  final SetLog? set;

  /// The next set due. Every unlogged chip is tappable and outlined; this one
  /// additionally carries the accent, so the eye lands on where to go next
  /// without that implying the others are closed.
  final bool isActive;

  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final semantic = context.semanticColors;
    final formatters = Formatters.of(context);
    final logged = set;

    final (background, foreground, border) = switch (logged?.status) {
      // Unlogged. Every one of these is tappable — you can log set 3 before
      // set 2 — so they all carry an outline. Only the next-due one gets the
      // accent, as a hint rather than a gate.
      null => (
        colors.surfaceContainerHigh,
        isActive ? colors.onSurface : colors.onSurfaceVariant,
        isActive ? colors.primary : colors.outlineVariant,
      ),
      SetStatus.done => (colors.primary, colors.onPrimary, Colors.transparent),
      SetStatus.partial => (
        semantic.warningContainer,
        semantic.onWarningContainer,
        Colors.transparent,
      ),
      SetStatus.skipped => (
        colors.errorContainer,
        colors.onErrorContainer,
        Colors.transparent,
      ),
      SetStatus.substituted => (
        colors.secondaryContainer,
        colors.onSecondaryContainer,
        Colors.transparent,
      ),
    };

    return Semantics(
      button: true,
      label: _semanticLabel(context, formatters),
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            borderRadius: AppRadius.smAll,
            child: AnimatedContainer(
              duration: AppDurations.base,
              curve: AppMotion.standard,
              // 64×48 fits "62.5×8" at the body size without ellipsis, and
              // clears the 48dp minimum target.
              width: 68,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: background,
                borderRadius: AppRadius.smAll,
                // The next-due chip's outline is heavier, so "available" and
                // "do this one next" read as two different things at a glance.
                border: Border.all(color: border, width: isActive ? 2 : 1),
              ),
              child: AnimatedSwitcher(
                duration: AppDurations.micro,
                child: _content(context, foreground, formatters),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(
    BuildContext context,
    Color foreground,
    Formatters formatters,
  ) {
    final logged = set;

    if (logged == null) {
      return Text(
        // The set number, so an empty grid still reads as "four sets".
        formatters.integer(setIndex + 1),
        key: ValueKey('empty-$setIndex'),
        style: context.textStyles.labelLarge?.copyWith(color: foreground),
      );
    }

    if (logged.isSkipped) {
      return Icon(
        Icons.remove_rounded,
        key: ValueKey('skipped-$setIndex'),
        size: 18,
        color: foreground,
      );
    }

    final weight = logged.weightKg;
    final reps = logged.reps;

    // Time-based work has no load or reps to show — a bike interval reads as
    // "10 min", which is the whole record of what was done.
    if (logged.durationSec case final seconds? when reps == null) {
      return Text(
        context.l10n.slotDurationMinutes((seconds / 60).round()),
        key: ValueKey('duration-$setIndex-$seconds'),
        style: context.textStyles.labelLarge?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w700,
        ),
        maxLines: 1,
      );
    }

    return Text(
      weight == null || reps == null
          ? formatters.integer(reps ?? 0)
          : '${formatters.decimal(weight, fractionDigits: weight % 1 == 0 ? 0 : 1)}'
                '×${formatters.integer(reps)}',
      key: ValueKey('logged-$setIndex-${logged.weightKg}-${logged.reps}'),
      style: context.textStyles.labelLarge?.copyWith(
        color: foreground,
        fontWeight: FontWeight.w700,
      ),
      maxLines: 1,
    );
  }

  String _semanticLabel(BuildContext context, Formatters formatters) {
    final l10n = context.l10n;
    final logged = set;

    if (logged == null) return l10n.sessionSetChip(setIndex + 1);
    if (logged.isSkipped) return l10n.skipTitle;

    final weight = logged.weightKg;
    final reps = logged.reps;

    if (logged.durationSec case final seconds? when reps == null) {
      return l10n.slotDurationMinutes((seconds / 60).round());
    }
    if (weight == null || reps == null) {
      return l10n.sessionSetChip(setIndex + 1);
    }

    return l10n.sessionPreviousSet(formatters.decimal(weight), reps);
  }
}
