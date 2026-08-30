import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';

/// The big screen title, with an optional trailing affordance — "Today" plus
/// its sync hairline, "Insights" plus its range filter.
///
/// A plain header rather than an `AppBar`: these screens scroll as one
/// document, and a collapsing bar would fight the hero card directly beneath.
class PageHeader extends StatelessWidget {
  const PageHeader(
    this.title, {
    super.key,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.only(bottom: AppSpacing.md),
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: theme.textTheme.titleLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (subtitle case final text?)
                  Text(
                    text,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (trailing case final widget?) ...[
            const SizedBox(width: AppSpacing.sm),
            widget,
          ],
        ],
      ),
    );
  }
}

/// Heading above a group of cards. Keeps section rhythm identical across
/// screens instead of each one inventing its own spacing.
class SectionLabel extends StatelessWidget {
  const SectionLabel(
    this.label, {
    super.key,
    this.trailing,
    this.padding = const EdgeInsets.only(
      top: AppSpacing.lg,
      bottom: AppSpacing.sm,
    ),
  });

  final String label;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.2,
    );

    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            // Uppercased for display only; the semantic label keeps the
            // original casing so a screen reader doesn't spell it out.
            child: Semantics(
              header: true,
              label: label,
              child: ExcludeSemantics(
                child: Text(label.toUpperCase(), style: style),
              ),
            ),
          ),
          if (trailing case final widget?)
            DefaultTextStyle.merge(style: style, child: widget),
        ],
      ),
    );
  }
}
