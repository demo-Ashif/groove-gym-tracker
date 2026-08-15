import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';
import '../../core/utils/extensions/context_extensions.dart';
import 'state_views.dart';

/// Scaffolding for a tab whose real content lands in a later milestone.
///
/// It is a *designed* empty state rather than a blank area, so navigating the
/// shell already reads as an app — and the milestone badge is there so a
/// placeholder that survives to release is obvious rather than quietly
/// shipping. Every use of this is deleted as its feature lands.
class RoadmapPlaceholder extends StatelessWidget {
  const RoadmapPlaceholder({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    required this.milestone,
  });

  final IconData icon;
  final String title;
  final String message;

  /// Which roadmap step fills this in, e.g. 'Phase 1'.
  final String milestone;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: EmptyView(icon: icon, title: title, message: message),
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xl),
          child: _MilestoneBadge(milestone: milestone),
        ),
      ],
    );
  }
}

class _MilestoneBadge extends StatelessWidget {
  const _MilestoneBadge({required this.milestone});

  final String milestone;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: AppRadius.fullAll,
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xxs + 2,
        ),
        child: Text(
          context.l10n.placeholderRoadmap(milestone),
          style: context.textStyles.labelSmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
