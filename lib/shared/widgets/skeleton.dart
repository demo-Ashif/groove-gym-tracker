import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';

/// Drives the pulse for every skeleton beneath it.
///
/// One controller per screen, not one per box — a loading list of twenty rows
/// would otherwise spin up twenty tickers. Skeletons still render (static)
/// without this ancestor, so a stray [SkeletonBox] can never crash a screen.
class Shimmer extends StatefulWidget {
  const Shimmer({super.key, required this.child});

  final Widget child;

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Honour the OS "reduce motion" setting (ADR §14.3): a looping pulse is
    // exactly the kind of thing it exists to stop. Skeletons still render,
    // just static.
    if (MediaQuery.disableAnimationsOf(context)) {
      if (_controller.isAnimating) _controller.stop();
      return widget.child;
    }

    if (!_controller.isAnimating) _controller.repeat();
    return _ShimmerScope(animation: _controller, child: widget.child);
  }
}

class _ShimmerScope extends InheritedWidget {
  const _ShimmerScope({required this.animation, required super.child});

  final Animation<double> animation;

  static Animation<double>? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ShimmerScope>()?.animation;

  @override
  bool updateShouldNotify(_ShimmerScope oldWidget) =>
      oldWidget.animation != animation;
}

/// A content-shaped placeholder block.
///
/// Size these like the real content they stand in for — that is the whole
/// point of a skeleton over a spinner: the layout must not jump when data
/// lands (ADR §13.6).
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height = 16,
    this.borderRadius,
    this.shape = BoxShape.rectangle,
  });

  /// Circular placeholder — icon wells, rings.
  const SkeletonBox.circle({super.key, required double size})
    : width = size,
      height = size,
      borderRadius = null,
      shape = BoxShape.circle;

  final double? width;
  final double height;
  final BorderRadius? borderRadius;
  final BoxShape shape;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final animation = _ShimmerScope.maybeOf(context);

    Widget box(double alpha) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: scheme.onSurfaceVariant.withValues(alpha: alpha),
        borderRadius: shape == BoxShape.circle
            ? null
            : borderRadius ?? AppRadius.smAll,
        shape: shape,
      ),
    );

    if (animation == null) return box(0.12);

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        // Sine pulse rather than a sweeping gradient: no shader per box, so a
        // long list stays cheap.
        final t = (math.sin(animation.value * 2 * math.pi) + 1) / 2;
        return box(0.06 + t * 0.08);
      },
    );
  }
}

/// A text-line placeholder. [widthFactor] lets the last line of a paragraph be
/// short, which is what makes skeleton text read as text.
class SkeletonLine extends StatelessWidget {
  const SkeletonLine({super.key, this.widthFactor = 1, this.height = 12});

  final double widthFactor;
  final double height;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      alignment: AlignmentDirectional.centerStart,
      widthFactor: widthFactor.clamp(0.05, 1.0),
      child: SkeletonBox(height: height),
    );
  }
}

/// Card-shaped placeholder matching [AppCard]'s footprint.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key, this.height = 84});

  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      height: height,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: const Row(
        children: [
          SkeletonBox.circle(size: 40),
          SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SkeletonLine(widthFactor: 0.45, height: 15),
                SizedBox(height: AppSpacing.xs),
                SkeletonLine(widthFactor: 0.75),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
