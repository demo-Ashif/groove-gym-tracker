# UI Polish: What Separates "Works" From "Feels Expensive"

Depth reference for the *feel* of a screen. Correct code that feels cheap is still a failed
deliverable — users read polish as trustworthiness long before they read your architecture.

The through-line: **premium apps acknowledge the user.** Every tap gets a reaction, every change is
followed by the eye, every state (including the boring ones) was deliberately designed, and the
visual system is consistent enough that nothing reads as accidental.

Most of what follows costs a few lines. Skipping it is what makes a screen look AI-generated.

## Contents

1. [Touch feedback — every tap gets a reaction](#1-touch-feedback)
2. [Motion — animate state changes, don't snap them](#2-motion)
3. [Empty states](#3-empty-states)
4. [Loading states — skeletons over spinners](#4-loading-states)
5. [Spacing from a system](#5-spacing)
6. [Typography with real hierarchy](#6-typography)
7. [Elevation and shadows with intention](#7-elevation--shadows)
8. [Haptics on moments that matter](#8-haptics)
9. [Design tokens — the file that makes 5–7 automatic](#9-design-tokens)
10. [Polish pass checklist](#10-polish-pass-checklist)

---

## 1. Touch feedback

A control that doesn't visibly respond feels broken even when it works — the user's second tap is
them assuming the first one failed. On a phone, the finger covers the target, so the ripple is often
the *only* confirmation the tap registered.

**Default to `InkWell`/`InkResponse` for anything tappable.** A bare `GestureDetector` has zero
visual feedback and should only appear where you're handling raw gestures (drag, scale, pan) or
where you've supplied your own press state.

```dart
// Reads as broken — nothing happens on press.
GestureDetector(onTap: _open, child: _card)

// Ripple, correct hit target, and it clips to the card's shape.
Material(
  color: Colors.transparent,
  child: InkWell(
    onTap: _open,
    borderRadius: BorderRadius.circular(16), // ripple must match the card radius
    child: _card,
  ),
)
```

Points that decide whether this looks right:

- **Ink splashes need a `Material` ancestor** and paint *above* it — an `InkWell` inside a
  `Container(color:)` shows nothing. Use `Material`/`Card` for the surface, or `Ink(decoration:)`
  when you need gradients or images under the ripple.
- **Match `borderRadius`/`customBorder` to the shape.** A square ripple bleeding out of a rounded
  card is worse than no ripple.
- **Minimum 48×48dp hit target** even when the glyph is smaller — wrap in `SizedBox`, use
  `IconButton`, or set `InkResponse.radius`. Tiny targets are the most common accessibility failure.
- **Custom-painted or scaled controls**: if a ripple doesn't suit, give a press state yourself —
  `AnimatedScale`/`AnimatedOpacity` driven by `onTapDown`/`onTapUp`/`onTapCancel`. Handle
  `onTapCancel`, or the widget sticks in its pressed state when the user drags off.
- **Disabled means `onTap: null`**, not an ignored callback — null suppresses the ripple and lets the
  theme grey it out, so the control tells the truth about its state.
- On desktop/web also give hover and focus states (`InkWell` handles both) and a `MouseCursor`.

---

## 2. Motion

When a value updates, the eye wants to follow it. An instant swap reads as a glitch; the same change
over ~200ms reads as intentional. You are not choreographing a motion-design system — you're
preventing discontinuity.

**Implicit widgets cover the overwhelming majority of it, with nothing to dispose:**

| Change | Widget |
|---|---|
| size, colour, padding, decoration | `AnimatedContainer` |
| one widget replaced by another | `AnimatedSwitcher` |
| appear / disappear | `AnimatedOpacity`, `AnimatedCrossFade` |
| position within a `Stack` | `AnimatedPositioned`, `AnimatedAlign` |
| a number counting up | `TweenAnimationBuilder` |
| list insert/remove | `AnimatedList` / `SliverAnimatedList` |
| any layout change in a subtree | `AnimatedSize` |

```dart
AnimatedSwitcher(
  duration: const Duration(milliseconds: 200),
  transitionBuilder: (child, anim) => FadeTransition(
    opacity: anim,
    child: ScaleTransition(scale: Tween(begin: .96, end: 1.0).animate(anim), child: child),
  ),
  // Without distinct keys the switcher sees "same widget" and won't animate.
  child: isLoading
      ? const _Skeleton(key: ValueKey('loading'))
      : _Content(key: ValueKey(data.id)),
)
```

Durations that read as designed: **150–250ms** for most state changes, ~100ms for micro-feedback,
300–400ms for full-screen or shared-element transitions. Past ~400ms the UI feels sluggish. Pair
with an easing curve — `Curves.easeOutCubic` for entrances, `easeInOut` for symmetric changes.
Linear motion looks mechanical.

Two things that trip people up: `AnimatedSwitcher` needs **different keys** on old and new children,
and any implicit widget animates only when it stays the same widget type in the same tree position.

Respect `MediaQuery.disableAnimations` (reduced motion) by shortening or skipping — a small check
that matters to real users. See `animations.md` when a change needs an explicit controller.

---

## 3. Empty states

A blank screen when there's no data is usually the **first thing a new user sees**, and an empty
screen with no explanation is indistinguishable from a broken one. Three jobs:

1. **Say why it's empty**, in one friendly line.
2. **Show an icon or illustration**, so the screen looks finished rather than failed.
3. **Give one clear action** that fills it — "Add your first habit" — not a dead end.

```dart
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title,
    required this.message, this.actionLabel, this.onAction});

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Insets.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: Insets.lg),
            Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: Insets.sm),
            Text(
              message,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            if (actionLabel != null) ...[
              const SizedBox(height: Insets.xl),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
```

Write the copy as a person, not a system: "No habits yet — add one to start tracking" beats "No data
available." **Error states earn the same treatment** (what happened, plus a Retry) — an error is just
an empty state with a cause. Build the component once per app and reuse it; a bespoke empty layout
per screen is how they drift.

---

## 4. Loading states

A centred spinner on a white screen communicates nothing and makes the wait feel longer. A
**skeleton** — grey placeholder shapes in the layout of the real content — makes it feel shorter,
because the brain already sees the structure and the content simply resolves into place.

Build the skeleton to **match the real layout's shape** (same rough heights, same spacing). If the
skeleton and the loaded content have different geometry, the screen visibly jumps and you've traded
one cheap moment for another.

The reliable way to guarantee that match is to **derive the skeleton from the real widget tree**
rather than hand-building a parallel one. A hand-written skeleton is duplicate work that silently
drifts — you update the real layout and forget the placeholder. `skeletonizer` (2.x, actively
maintained) wraps the actual layout and paints it as bones:

```dart
// skeletonizer: ^2.1.1
Skeletonizer(
  enabled: isLoading,
  child: ListView.builder(
    itemCount: isLoading ? 6 : items.length,
    itemBuilder: (_, i) {
      // While loading, feed placeholder data of realistic length so the
      // bones size correctly — BoneMock gives you plausible fake text.
      final item = isLoading ? Item.mock() : items[i];
      return ListTile(
        leading: const CircleAvatar(),
        title: Text(item.title),
        subtitle: Text(item.subtitle),
      );
    },
  ),
)
```

Useful annotations: `Skeleton.ignore` (exclude a subtree from bone painting), `Skeleton.keep` (render
it normally — icons, dividers), `Skeleton.replace` (swap in a differently-shaped bone), and
`Bone.text()` when you want an explicit placeholder. Theme it once via the `SkeletonizerConfigData`
theme extension (light + dark) so every skeleton in the app matches.

`shimmer` still works and is widely used, but it hasn't shipped a release since 2023 and it makes you
hand-build the placeholder layout — prefer `skeletonizer` for new work unless the codebase already
standardized on shimmer. (Package health shifts over time; if this file looks old, confirm on pub.dev
before committing to a dependency.)

Rules of thumb:

- Skeletons for **content-shaped** waits (lists, cards, profiles). A spinner is still right for a
  short indeterminate action inside a button, and a **progress bar** whenever you know the
  percentage — never fake a determinate bar.
- For **fast** loads, a spinner that flashes for 80ms is worse than none: gate on a short delay, or
  keep the previous content visible with a subtle overlay.
- Buttons that trigger async work should show inline progress **and disable themselves** — this
  doubles as your double-submit guard.
- Pair with `AnimatedSwitcher` (§2) so loading→content cross-fades instead of snapping.
- Drive all of this from explicit async state (`AsyncValue`, sealed state classes), not loose
  booleans — see `state-management.md`. Every async surface owes the user four designed states:
  **loading, data, empty, error.**

---

## 5. Spacing

Ad-hoc padding (13 here, 18 there) reads as sloppy even when nobody can name why — the eye detects
the inconsistency without identifying it. Pick a scale, derive everything from it.

**A 4pt base is the standard**: 4, 8, 12, 16, 20, 24, 32, 40, 48. Expose it as constants (see §9) and
reference the token, never the raw number: `const EdgeInsets.all(Insets.md)`.

- Space **within** a group is smaller than space **between** groups — that contrast is what creates
  visual grouping without drawing a single border.
- Keep one page gutter (commonly 16 or 20) and use it on every screen; inconsistent gutters are the
  most visible violation because the eye tracks the left edge down the whole app.
- Same idea for **radii** — one scale (e.g. 8 / 12 / 16 / full) rather than a new value per widget.

If a value can't be justified from the scale, it's a bug, not taste.

---

## 6. Typography

If title, body, and caption all look about the same size, the screen feels flat and the user has no
idea where to look first. Hierarchy is what makes a layout scannable, and contrast does the work:
**bold and larger** for the title against **lighter and smaller** supporting text.

Define the `TextTheme` **once** in the app theme and pull from it — `Theme.of(context).textTheme.
titleMedium` — instead of hand-writing `TextStyle(fontSize: 18, ...)` at call sites. Local styles are
how an app ends up with nine slightly different heading sizes, and they silently break dark mode.

```dart
textTheme: TextTheme(
  headlineSmall: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w700, height: 1.25),
  titleMedium:   GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w600, height: 1.3),
  bodyMedium:    GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w400, height: 1.45),
  labelSmall:    GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, height: 1.35),
),
```

- Convey secondary text with **colour** (`onSurfaceVariant`), not just a smaller size — lighter grey
  reads as "supporting" instantly.
- Set **`height`** (line height ~1.3–1.5 for body). Default leading is the quiet reason dense text
  looks cramped.
- Keep the ramp small — roughly 4–6 styles for a whole app. More is drift, not expressiveness.
- **Never disable text scaling** to fix an overflow; fix the layout. Sanity-check the screen at ~1.3×
  system font size.

---

## 7. Elevation & shadows

Heavy, hard default shadows are the clearest "stock widget" tell. Physical light is soft: **low
opacity, generous blur, small vertical offset, no spread.** Two stacked soft shadows (one tight and
faint for contact, one wide and fainter for ambient depth) look markedly more expensive than one
hard drop shadow.

```dart
static const softLift = [
  BoxShadow(color: Color(0x0D000000), blurRadius: 4,  offset: Offset(0, 1)),  // ~5% contact
  BoxShadow(color: Color(0x14000000), blurRadius: 20, offset: Offset(0, 8)),  // ~8% ambient
];
```

- Elevation should **mean** something: raised = interactive or floating (cards, sheets, FAB), flat =
  static content. Everything shadowed is the same as nothing shadowed.
- Prefer `Card`/`Material` with a tuned `elevation` + `shadowColor`, or a `Container` with an
  explicit `boxShadow` — the default `Card` elevation is usually heavier than you want.
- In **dark mode**, black shadows barely register: separate surfaces with lighter background colours
  or M3 `surfaceContainer` tones / `surfaceTintColor` rather than pushing shadow opacity up.
- A **1px hairline border** (`outlineVariant`) is often cleaner than a shadow for dividing content —
  and cheaper to render.

---

## 8. Haptics

A short vibration on a meaningful action makes the app feel physical — like the interface has mass.
The whole effect depends on **restraint**: haptics on every tap become noise the user turns off.

```dart
import 'package:flutter/services.dart';

HapticFeedback.mediumImpact(); // task completed, purchase confirmed, milestone hit
```

Rough mapping:

- `selectionClick()` — passing a discrete step: picker/slider notches, segmented control, tab switch.
- `lightImpact()` — small confirmations: toggle, chip select, pull-to-refresh trip.
- `mediumImpact()` — the moments that deserve a beat: task completed, purchase, streak, form
  submitted successfully.
- `heavyImpact()` — rare and weighty: destructive confirm, game-over, hard failure.

Reserve it for **completion, confirmation, and error** — not navigation or scrolling. iOS gives the
richest feedback; Android varies by device and user settings, so treat haptics as *enhancement, never
the only signal* (always pair with the visual change). Note that some Android feedback requires the
`VIBRATE` permission — verify before depending on it. If the app has a settings screen, let users
turn haptics off, and route calls through one small helper so that switch has a single place to
apply.

---

## 9. Design tokens

Sections 5–7 only stay consistent if the values live in one place. A tiny tokens file makes the right
thing the easy thing — and makes a redesign a one-file change instead of a grep.

```dart
// lib/core/theme/tokens.dart
abstract final class Insets {
  static const xs = 4.0, sm = 8.0, md = 16.0, lg = 24.0, xl = 32.0;
}

abstract final class Radii {
  static const sm = 8.0, md = 12.0, lg = 16.0;
  static const card = BorderRadius.all(Radius.circular(md));
}

abstract final class Motion {
  static const fast = Duration(milliseconds: 150);
  static const base = Duration(milliseconds: 200);
  static const slow = Duration(milliseconds: 350);
  static const curve = Curves.easeOutCubic;
}
```

Colours belong in `ColorScheme` (light + dark), text in `TextTheme`, component defaults in the
`ThemeData` component themes (`filledButtonTheme`, `cardTheme`, `inputDecorationTheme`) — set them
once so individual widgets stay clean and dark mode works for free. Reach for `ThemeExtension` when
the app needs custom semantic colours (success, warning, brand surfaces) that `ColorScheme` doesn't
cover.

---

## 10. Polish pass checklist

Run this over any screen before delivering. These are the items that decide whether it reads as
premium or as a wireframe.

- [ ] Every tappable element gives visual feedback (ripple or custom press state) and has a ≥48dp target
- [ ] `InkWell`/`InkResponse` over bare `GestureDetector`; ripple shape matches the widget's radius
- [ ] Disabled controls pass `null` (not an ignored callback) and look disabled
- [ ] State changes animate (~150–250ms) with an intentional curve, not an instant snap
- [ ] `AnimatedSwitcher` children carry distinct keys; reduced-motion respected
- [ ] Empty state designed: reason + icon/illustration + one clear action — never a blank screen
- [ ] Error state designed: what happened + retry
- [ ] Loading uses a skeleton matching the real layout (or inline/determinate progress); no bare
      centred spinner on an empty screen, no layout jump when content lands
- [ ] Async buttons show inline progress and disable while in flight
- [ ] All spacing comes from the scale (4pt base) via tokens — no ad-hoc 13s and 18s; one page gutter
- [ ] Type comes from `TextTheme` with real hierarchy (size + weight + colour), sensible `height`,
      and survives ~1.3× text scaling
- [ ] Shadows are soft and low-opacity (layered where it matters); elevation carries meaning; dark
      mode separates surfaces with tone, not black shadow
- [ ] Haptics on completion/confirmation/error moments only — paired with a visual change, never alone
- [ ] Colours, radii, durations, and insets come from theme/tokens, not magic numbers
