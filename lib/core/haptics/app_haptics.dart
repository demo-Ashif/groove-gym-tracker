import 'package:flutter/services.dart';

/// Haptic vocabulary (ADR §14.3).
///
/// Three rules, enforced here rather than left to call sites:
/// 1. **Never alone.** Every method below is meant to accompany a visual
///    change. A buzz with nothing on screen reads as a bug.
/// 2. **Never in a loop.** [selection] is throttled to one tick per 60ms, so
///    holding a stepper's `+` produces a rhythm rather than a rattle.
/// 3. **Always skippable.** A single toggle in Profile silences everything.
///
/// Registered as a singleton so the toggle has one owner; the preferences
/// cubit pushes changes in via [enabled].
class AppHaptics {
  AppHaptics({bool enabled = true}) : _enabled = enabled;

  /// ADR §14.3: throttle selection ticks to ≥60ms.
  static const _minInterval = Duration(milliseconds: 60);

  bool _enabled;
  DateTime? _lastSelection;

  bool get enabled => _enabled;

  set enabled(bool value) {
    _enabled = value;
    if (!value) _lastSelection = null;
  }

  /// Set chip logged, stepper increment, ruler notch.
  void selection() {
    if (!_enabled) return;

    final now = DateTime.now();
    final last = _lastSelection;
    if (last != null && now.difference(last) < _minInterval) return;

    _lastSelection = now;
    HapticFeedback.selectionClick();
  }

  /// Exercise completed.
  void light() {
    if (!_enabled) return;
    HapticFeedback.lightImpact();
  }

  /// Session finalized, rest timer done.
  void medium() {
    if (!_enabled) return;
    HapticFeedback.mediumImpact();
  }

  /// New PR. The loudest thing in the app, and it fires roughly once a week.
  void heavy() {
    if (!_enabled) return;
    HapticFeedback.heavyImpact();
  }

  /// Blocked action — a short buzz, paired with whatever visual says no.
  void blocked() {
    if (!_enabled) return;
    HapticFeedback.vibrate();
  }
}
