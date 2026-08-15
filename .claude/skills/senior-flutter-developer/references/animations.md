# Animations: Implicit, Explicit & Custom

Depth reference for smooth, leak-free Flutter animation. The golden rule: **every
`AnimationController` is created with a `vsync` and disposed in `dispose()`** — and you animate the
smallest subtree possible.

## Pick the lightest tool that works

1. **Implicit** (`AnimatedContainer`, `AnimatedOpacity`, `AnimatedPositioned`,
   `AnimatedAlign`, `TweenAnimationBuilder`, …) — for simple A→B transitions on property change. No
   controller to manage, nothing to dispose. Reach here first.
2. **Explicit** (`AnimationController` + `Tween`/`CurvedAnimation`, driven via
   `AnimatedBuilder`/`AnimatedWidget`/transition widgets) — when you need to start/stop/reverse/
   repeat, sequence, or coordinate multiple values.
3. **Custom** (`CustomPainter`, `AnimatedBuilder` over a painter, or `flutter_animate` if the
   project allows) — for bespoke drawing, progress arcs, particles, path morphs.

For pre-built page/element transitions, prefer the `animations` package
(`OpenContainer`, `PageTransitionSwitcher`, shared-axis/fade-through) before hand-rolling.

## Explicit animation — the correct skeleton

```dart
class Pulse extends StatefulWidget {
  const Pulse({super.key, required this.child});
  final Widget child;
  @override
  State<Pulse> createState() => _PulseState();
}

class _PulseState extends State<Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,                                   // ticker bound to this State
    duration: const Duration(milliseconds: 800),
  )..repeat(reverse: true);

  late final Animation<double> _scale =
      Tween(begin: 1.0, end: 1.15).animate(
        CurvedAnimation(parent: _c, curve: Curves.easeInOut),
      );

  @override
  void dispose() {
    _c.dispose();              // <- ticker leak if omitted
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild ONLY the animated subtree; pass the static child through.
    return AnimatedBuilder(
      animation: _scale,
      child: widget.child,
      builder: (_, child) => Transform.scale(scale: _scale.value, child: child),
    );
  }
}
```

Key points:
- **`SingleTickerProviderStateMixin`** for one controller, **`TickerProviderStateMixin`** for
  several. The mixin is what makes `vsync: this` work and pauses tickers when the route is offscreen.
- Use the **`child` parameter** of `AnimatedBuilder`/transition builders to keep the non-animating
  subtree from rebuilding every frame.
- Drive transforms via `Transform`, `Opacity`, `Align`, `FractionalTranslation`, or the dedicated
  `FadeTransition`/`ScaleTransition`/`SlideTransition` widgets (cheaper than rebuilding layout).

## Staggered animations

One controller, multiple tweens over `Interval`s — don't spin up a controller per element:

```dart
final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));

late final _fade  = CurvedAnimation(parent: _c, curve: const Interval(0.0, 0.5));
late final _slide = Tween(begin: const Offset(0, .2), end: Offset.zero)
    .animate(CurvedAnimation(parent: _c, curve: const Interval(0.3, 1.0, curve: Curves.easeOut)));
```

For list intro sequences, prefer the `flutter_staggered_animations` package or a single controller
with computed per-index intervals rather than N controllers.

## Custom painting + animation

```dart
class RingPainter extends CustomPainter {
  RingPainter(this.progress);
  final double progress; // 0..1, fed from the controller
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round;
    final rect = Offset.zero & size;
    canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * progress, false, paint);
  }
  @override
  bool shouldRepaint(RingPainter old) => old.progress != progress; // repaint only when it changes
}
```

- Implement **`shouldRepaint`** precisely — returning `true` always repaints every frame for nothing.
- Wrap an animating painter (or any heavy, independently-animating subtree) in **`RepaintBoundary`**
  so it doesn't dirty siblings.

## Hero & shared-element

- Matching `Hero(tag: ...)` on both routes; tags must be unique per screen. Keep hero children cheap;
  use `flightShuttleBuilder` for custom mid-flight widgets. Avoid heroes around `ListView` items with
  duplicate tags — it throws.

## Performance checklist

- [ ] Controllers created with `vsync` and **disposed**; no `Timer`-driven `setState` animation loops.
- [ ] Only the animated subtree rebuilds (`AnimatedBuilder` `child:`, narrow `Listenable`s).
- [ ] `RepaintBoundary` around independently-animating / expensive painters.
- [ ] `CustomPainter.shouldRepaint` returns `false` when nothing changed.
- [ ] Prefer transform/opacity transitions over animating layout (width/height/padding) where possible.
- [ ] Curves chosen intentionally (`Curves.easeInOut`, `easeOutCubic`, …) — linear motion looks robotic.
- [ ] Respect reduced-motion: check `MediaQuery.disableAnimations`/accessibility and tone down or skip.
- [ ] Test on a real device in profile mode for jank, not just the simulator.
