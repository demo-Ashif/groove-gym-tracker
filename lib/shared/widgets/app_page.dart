import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';

/// Standard tab-page frame: one gutter, one max content width, one safe-area
/// policy.
///
/// Every tab uses this so the page rhythm is identical across the app and a
/// change to the gutter is a single edit. The bottom edge is deliberately not
/// inset — the shell's navigation bar already reserves that space, and a
/// second inset would leave a dead band above it.
class AppPage extends StatelessWidget {
  const AppPage({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AppSizes.maxContentWidth),
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: AppSpacing.gutter,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
