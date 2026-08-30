import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/haptics/app_haptics.dart';
import '../../../../domain/entities/insights.dart';
import '../../../../domain/values/calendar_date.dart';

/// Body weight over the selected window (ADR §11.2 card 2).
///
/// Raw weigh-ins are faint dots and the moving average is the heavy line,
/// because a single morning swings more than a kilo on water alone — reading
/// the dots as the trend is the mistake this chart exists to prevent.
///
/// Drawn by hand rather than with a charting package: the whole surface is
/// three shapes, and a dependency would bring its own theming, its own text
/// scaling and its own idea of what a tooltip looks like.
class WeightTrendChart extends StatefulWidget {
  const WeightTrendChart({
    super.key,
    required this.points,
    required this.formatWeight,
    required this.formatDate,
    this.phaseBoundaries = const [],
    this.height = 168,
  });

  final List<WeightPoint> points;

  /// Phase starts inside the window, drawn as vertical rules — a step in the
  /// trend usually belongs to a block change.
  final List<CalendarDate> phaseBoundaries;

  final String Function(double kg) formatWeight;
  final String Function(CalendarDate date) formatDate;

  final double height;

  @override
  State<WeightTrendChart> createState() => _WeightTrendChartState();
}

class _WeightTrendChartState extends State<WeightTrendChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppDurations.chart,
  );

  final AppHaptics _haptics = getIt<AppHaptics>();

  /// Which weigh-in the tooltip is pinned to. Null until the user touches.
  int? _selected;

  /// The draw-in runs once per appearance, never per rebuild (ADR §11.4).
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(WeightTrendChart old) {
    super.didUpdateWidget(old);
    // A new window means new points, and a selection index from the old list
    // would either point at the wrong day or off the end of the new one.
    if (!identical(old.points, widget.points) &&
        old.points.length != widget.points.length) {
      _selected = null;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _selectAt(double dx, _ChartGeometry geometry) {
    final index = geometry.nearestIndex(dx);
    if (index == _selected) return;

    setState(() => _selected = index);
    // Paired with the tooltip appearing — never a buzz on its own
    // (ADR §14.3).
    _haptics.selection();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final geometry = _ChartGeometry(
            size: Size(constraints.maxWidth, widget.height),
            points: widget.points,
            boundaries: widget.phaseBoundaries,
          );

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) =>
                _selectAt(details.localPosition.dx, geometry),
            onHorizontalDragStart: (details) =>
                _selectAt(details.localPosition.dx, geometry),
            onHorizontalDragUpdate: (details) =>
                _selectAt(details.localPosition.dx, geometry),
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  return CustomPaint(
                    size: Size(constraints.maxWidth, widget.height),
                    painter: _WeightChartPainter(
                      geometry: geometry,
                      progress: Curves.easeOutCubic.transform(
                        _controller.value,
                      ),
                      selectedIndex: _selected,
                      lineColor: scheme.primary,
                      dotColor: scheme.onSurfaceVariant.withValues(alpha: 0.35),
                      gridColor: scheme.outlineVariant,
                      labelColor: scheme.onSurfaceVariant,
                      tooltipColor: scheme.inverseSurface,
                      onTooltipColor: scheme.onInverseSurface,
                      labelStyle:
                          theme.textTheme.labelSmall ?? const TextStyle(),
                      textScaler: MediaQuery.textScalerOf(context),
                      textDirection: Directionality.of(context),
                      formatWeight: widget.formatWeight,
                      formatDate: widget.formatDate,
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Where every point lands. Shared by the painter and the hit test, so a tap
/// can never select a dot other than the one under the finger.
class _ChartGeometry {
  _ChartGeometry({
    required this.size,
    required this.points,
    required this.boundaries,
  }) {
    if (points.isEmpty) {
      minKg = 0;
      maxKg = 0;
      return;
    }

    var lowest = double.infinity;
    var highest = double.negativeInfinity;
    for (final point in points) {
      lowest = math.min(lowest, math.min(point.kg, point.averageKg ?? point.kg));
      highest = math.max(
        highest,
        math.max(point.kg, point.averageKg ?? point.kg),
      );
    }

    // A flat series would divide by zero; half a kilo of headroom also stops a
    // one-point chart drawing its dot on the frame's edge.
    if (highest - lowest < 0.5) {
      final middle = (highest + lowest) / 2;
      lowest = middle - 0.5;
      highest = middle + 0.5;
    }

    final padding = (highest - lowest) * 0.15;
    minKg = lowest - padding;
    maxKg = highest + padding;
  }

  final Size size;
  final List<WeightPoint> points;
  final List<CalendarDate> boundaries;

  late final double minKg;
  late final double maxKg;

  static const _inset = AppSpacing.xs;
  static const _bottomGutter = 18.0;

  double get _left => _inset;
  double get _right => size.width - _inset;
  double get _top => _inset;
  double get _bottom => size.height - _bottomGutter;

  int get _spanDays => points.isEmpty
      ? 0
      : points.first.date.daysUntil(points.last.date);

  double xForDate(CalendarDate date) {
    if (points.isEmpty) return _left;
    if (_spanDays <= 0) return (_left + _right) / 2;

    final offset = points.first.date.daysUntil(date) / _spanDays;
    return _left + (_right - _left) * offset.clamp(0.0, 1.0);
  }

  double xAt(int index) => xForDate(points[index].date);

  double yForKg(double kg) {
    final range = maxKg - minKg;
    if (range <= 0) return (_top + _bottom) / 2;
    final t = (kg - minKg) / range;
    return _bottom - (_bottom - _top) * t.clamp(0.0, 1.0);
  }

  Offset rawOffset(int index) =>
      Offset(xAt(index), yForKg(points[index].kg));

  Offset averageOffset(int index) => Offset(
    xAt(index),
    yForKg(points[index].averageKg ?? points[index].kg),
  );

  /// The point nearest a horizontal touch position.
  int nearestIndex(double dx) {
    var best = 0;
    var bestDistance = double.infinity;
    for (var i = 0; i < points.length; i++) {
      final distance = (xAt(i) - dx).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        best = i;
      }
    }
    return best;
  }
}

class _WeightChartPainter extends CustomPainter {
  const _WeightChartPainter({
    required this.geometry,
    required this.progress,
    required this.selectedIndex,
    required this.lineColor,
    required this.dotColor,
    required this.gridColor,
    required this.labelColor,
    required this.tooltipColor,
    required this.onTooltipColor,
    required this.labelStyle,
    required this.textScaler,
    required this.textDirection,
    required this.formatWeight,
    required this.formatDate,
  });

  final _ChartGeometry geometry;
  final double progress;
  final int? selectedIndex;
  final Color lineColor;
  final Color dotColor;
  final Color gridColor;
  final Color labelColor;
  final Color tooltipColor;
  final Color onTooltipColor;
  final TextStyle labelStyle;
  final TextScaler textScaler;
  final TextDirection textDirection;
  final String Function(double kg) formatWeight;
  final String Function(CalendarDate date) formatDate;

  @override
  void paint(Canvas canvas, Size size) {
    final points = geometry.points;
    if (points.isEmpty) return;

    _paintGrid(canvas);
    _paintBoundaries(canvas);
    _paintRawPoints(canvas);
    _paintAverage(canvas);
    _paintAxisLabels(canvas);
    _paintSelection(canvas);
  }

  void _paintGrid(Canvas canvas) {
    final paint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    for (final kg in [geometry.maxKg, geometry.minKg]) {
      _dashedLine(
        canvas,
        Offset(geometry._left, geometry.yForKg(kg)),
        Offset(geometry._right, geometry.yForKg(kg)),
        paint,
      );
    }
  }

  void _paintBoundaries(Canvas canvas) {
    if (geometry.boundaries.isEmpty || geometry.points.length < 2) return;

    final paint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    final first = geometry.points.first.date;
    final last = geometry.points.last.date;

    for (final boundary in geometry.boundaries) {
      // A rule outside the plotted span would be drawn on the frame, implying
      // a phase change at an edge where none happened.
      if (boundary.isBefore(first) || boundary.isAfter(last)) continue;

      final x = geometry.xForDate(boundary);
      _dashedLine(
        canvas,
        Offset(x, geometry._top),
        Offset(x, geometry._bottom),
        paint,
      );
    }
  }

  void _paintRawPoints(Canvas canvas) {
    final paint = Paint()..color = dotColor.withValues(alpha: dotColor.a * progress);

    for (var i = 0; i < geometry.points.length; i++) {
      canvas.drawCircle(geometry.rawOffset(i), 2.5, paint);
    }
  }

  void _paintAverage(Canvas canvas) {
    final points = geometry.points;

    if (points.length == 1) {
      canvas.drawCircle(
        geometry.averageOffset(0),
        4 * progress,
        Paint()..color = lineColor,
      );
      return;
    }

    final path = Path()..moveTo(
      geometry.averageOffset(0).dx,
      geometry.averageOffset(0).dy,
    );
    for (var i = 1; i < points.length; i++) {
      final offset = geometry.averageOffset(i);
      path.lineTo(offset.dx, offset.dy);
    }

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = lineColor;

    // The line strokes itself on rather than fading in — the draw-in is what
    // makes the trend read as a direction rather than as a picture.
    for (final metric in path.computeMetrics()) {
      canvas.drawPath(
        metric.extractPath(0, metric.length * progress),
        paint,
      );
    }
  }

  void _paintAxisLabels(Canvas canvas) {
    final points = geometry.points;

    _text(
      canvas,
      formatWeight(geometry.maxKg),
      Offset(geometry._left, geometry._top),
      labelColor,
    );
    _text(
      canvas,
      formatDate(points.first.date),
      Offset(geometry._left, geometry._bottom + 2),
      labelColor,
    );

    if (points.length > 1) {
      final label = _painterFor(formatDate(points.last.date), labelColor);
      label.paint(
        canvas,
        Offset(geometry._right - label.width, geometry._bottom + 2),
      );
    }
  }

  void _paintSelection(Canvas canvas) {
    final index = selectedIndex;
    if (index == null || index >= geometry.points.length) return;

    final point = geometry.points[index];
    final anchor = geometry.rawOffset(index);

    canvas.drawLine(
      Offset(anchor.dx, geometry._top),
      Offset(anchor.dx, geometry._bottom),
      Paint()
        ..color = lineColor.withValues(alpha: 0.5)
        ..strokeWidth = 1,
    );
    canvas.drawCircle(anchor, 4.5, Paint()..color = lineColor);

    final label = _painterFor(
      '${formatWeight(point.kg)} · ${formatDate(point.date)}',
      onTooltipColor,
    );

    const padding = AppSpacing.xs;
    final width = label.width + padding * 2;
    final height = label.height + padding;

    // Clamped so the tooltip never leaves the chart at either edge.
    final left = clampDouble(
      anchor.dx - width / 2,
      geometry._left,
      math.max(geometry._left, geometry._right - width),
    );
    final top = math.max(geometry._top, anchor.dy - height - 10);

    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, top, width, height),
      const Radius.circular(AppRadius.sm),
    );
    canvas.drawRRect(rect, Paint()..color = tooltipColor);
    label.paint(canvas, Offset(left + padding, top + padding / 2));
  }

  void _dashedLine(Canvas canvas, Offset from, Offset to, Paint paint) {
    const dash = 4.0;
    const gap = 4.0;

    final total = (to - from).distance;
    if (total <= 0) return;

    final direction = (to - from) / total;
    var travelled = 0.0;
    while (travelled < total) {
      final end = math.min(travelled + dash, total);
      canvas.drawLine(
        from + direction * travelled,
        from + direction * end,
        paint,
      );
      travelled = end + gap;
    }
  }

  TextPainter _painterFor(String text, Color color) {
    return TextPainter(
      text: TextSpan(text: text, style: labelStyle.copyWith(color: color)),
      textDirection: textDirection,
      textScaler: textScaler,
      maxLines: 1,
    )..layout();
  }

  void _text(Canvas canvas, String text, Offset at, Color color) =>
      _painterFor(text, color).paint(canvas, at);

  @override
  bool shouldRepaint(_WeightChartPainter old) =>
      old.progress != progress ||
      old.selectedIndex != selectedIndex ||
      !identical(old.geometry.points, geometry.points) ||
      old.geometry.size != geometry.size ||
      old.lineColor != lineColor ||
      old.labelStyle != labelStyle ||
      old.textScaler != textScaler;
}
