import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/haptics/app_haptics.dart';
import '../../../../core/utils/extensions/context_extensions.dart';
import '../../../../core/utils/formatters.dart';

/// The rest countdown: a hairline bar under the app bar, shifting from accent
/// to warning in the last ten seconds (ADR §14.2).
///
/// **Elapsed time is read from the clock, never accumulated.** The ticker only
/// decides when to repaint; if the OS suspends the app for two minutes
/// mid-rest, the bar comes back finished rather than resuming where it paused.
class RestTimerBar extends StatefulWidget {
  const RestTimerBar({
    super.key,
    required this.startedAt,
    required this.totalSeconds,
    required this.onDismiss,
  });

  final DateTime startedAt;
  final int totalSeconds;
  final VoidCallback onDismiss;

  @override
  State<RestTimerBar> createState() => _RestTimerBarState();
}

class _RestTimerBarState extends State<RestTimerBar> {
  Timer? _ticker;
  bool _finishedHapticSent = false;

  @override
  void initState() {
    super.initState();
    _startTicker();
  }

  @override
  void didUpdateWidget(RestTimerBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.startedAt != widget.startedAt) {
      _finishedHapticSent = false;
      _startTicker();
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    // One tick a second is enough for a countdown; a 60fps animation here
    // would burn battery for a bar that moves a pixel a second.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});

      if (_remaining <= Duration.zero && !_finishedHapticSent) {
        _finishedHapticSent = true;
        getIt<AppHaptics>().medium();
      }
    });
  }

  Duration get _remaining {
    final elapsed = DateTime.now().difference(widget.startedAt);
    final total = Duration(seconds: widget.totalSeconds);
    final left = total - elapsed;
    return left.isNegative ? Duration.zero : left;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final formatters = Formatters.of(context);
    final remaining = _remaining;
    final total = widget.totalSeconds;

    final progress = total <= 0
        ? 1.0
        : (1 - remaining.inMilliseconds / (total * 1000)).clamp(0.0, 1.0);

    final isEnding = remaining.inSeconds <= 10;
    final color = isEnding
        ? context.semanticColors.warning
        : context.colors.primary;

    return Material(
      color: context.colors.surfaceContainer,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // RepaintBoundary because this repaints every second while the rest
          // of the screen does not.
          RepaintBoundary(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: progress),
              duration: AppDurations.base,
              curve: AppMotion.standard,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 3,
                color: color,
                backgroundColor: context.colors.surfaceContainerHighest,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.gutter,
              AppSpacing.xxs,
              AppSpacing.xs,
              AppSpacing.xxs,
            ),
            child: Row(
              children: [
                Text(
                  l10n.restTimerLabel,
                  style: context.textStyles.labelMedium?.copyWith(
                    color: context.colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  formatters.clock(remaining),
                  style: context.textStyles.labelLarge?.copyWith(color: color),
                ),
                const Spacer(),
                TextButton(
                  onPressed: widget.onDismiss,
                  child: Text(l10n.restSkip),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
