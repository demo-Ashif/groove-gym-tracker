import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../app/theme/app_tokens.dart';

/// The adherence ring (ADR §11.2 card 1, §14.2).
///
/// Sweeps from zero on every value change rather than tweening between two
/// percentages: the sweep is what makes the number read as *earned* over the
/// window rather than as a gauge drifting about.
class AdherenceRing extends StatelessWidget {
  const AdherenceRing({
    super.key,
    required this.value,
    required this.label,
    required this.caption,
    this.size = 108,
    this.strokeWidth = 10,
  });

  /// 0–1, or null when nothing was planned — the ring then draws its track
  /// only, because "0%" would be a claim the data does not support.
  final double? value;

  /// The big number in the middle, already formatted.
  final String label;

  /// The line under it.
  final String caption;

  final double size;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final target = (value ?? 0).clamp(0.0, 1.0);

    // Honour the OS "reduce motion" setting (ADR §14.3): the ring appears at
    // its final value instead of sweeping.
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : AppDurations.chart;

    return RepaintBoundary(
      child: SizedBox.square(
        dimension: size,
        child: TweenAnimationBuilder<double>(
          // Keying on the value restarts the tween from zero whenever it
          // changes, which is the sweep the ADR asks for.
          key: ValueKey(target),
          tween: Tween(begin: 0, end: target),
          duration: duration,
          curve: AppMotion.standard,
          builder: (context, progress, child) {
            return CustomPaint(
              painter: _RingPainter(
                progress: progress,
                trackColor: scheme.surfaceContainerHighest,
                progressColor: scheme.primary,
                strokeWidth: strokeWidth,
                hasTarget: value != null,
              ),
              child: child,
            );
          },
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: theme.textTheme.titleLarge,
                  maxLines: 1,
                ),
                Text(
                  caption,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
    required this.strokeWidth,
    required this.hasTarget,
  });

  final double progress;
  final Color trackColor;
  final Color progressColor;
  final double strokeWidth;
  final bool hasTarget;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    if (radius <= 0) return;

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = trackColor;

    canvas.drawCircle(center, radius, track);

    if (!hasTarget || progress <= 0) return;

    final sweep = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = progressColor;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      // Twelve o'clock, clockwise — where every progress ring starts.
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      sweep,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.trackColor != trackColor ||
      old.progressColor != progressColor ||
      old.strokeWidth != strokeWidth ||
      old.hasTarget != hasTarget;
}
