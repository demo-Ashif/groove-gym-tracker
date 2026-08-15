import 'package:flutter/widgets.dart';

/// Material 3 window-size breakpoints.
abstract final class Breakpoints {
  static const double tablet = 600;
  static const double desktop = 1024;
}

enum ScreenSize { mobile, tablet, desktop }

extension ResponsiveContext on BuildContext {
  ScreenSize get screenSize {
    final width = MediaQuery.sizeOf(this).width;
    if (width >= Breakpoints.desktop) return ScreenSize.desktop;
    if (width >= Breakpoints.tablet) return ScreenSize.tablet;
    return ScreenSize.mobile;
  }

  bool get isMobile => screenSize == ScreenSize.mobile;
  bool get isTablet => screenSize == ScreenSize.tablet;
  bool get isDesktop => screenSize == ScreenSize.desktop;

  /// Picks a value per screen size, falling back to the next smaller one:
  /// `gutter = context.responsive(mobile: 20.0, tablet: 32.0)`.
  T responsive<T>({required T mobile, T? tablet, T? desktop}) =>
      switch (screenSize) {
        ScreenSize.desktop => desktop ?? tablet ?? mobile,
        ScreenSize.tablet => tablet ?? mobile,
        ScreenSize.mobile => mobile,
      };
}
