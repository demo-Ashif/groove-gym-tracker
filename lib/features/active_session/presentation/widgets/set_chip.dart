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

  /// The next set due — outlined in the accent so the eye lands on it without
  /// reading anything.
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
      null => (
        colors.surfaceContainerHigh,
        colors.onSurfaceVariant,
        isActive ? colors.primary : Colors.transparent,
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
                border: Border.all(color: border, width: 2),
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
    if (weight == null || reps == null) {
      return l10n.sessionSetChip(setIndex + 1);
    }

    return l10n.sessionPreviousSet(formatters.decimal(weight), reps);
  }
}
