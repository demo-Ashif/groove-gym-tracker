import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';
import '../../app/theme/groove_palette.dart';

/// The app's standard surface: 16dp radius, surface-container fill, a hairline
/// and a soft low-opacity shadow (ADR §13.2, §13.4).
///
/// Those four together are what make a card read as an object rather than a
/// coloured rectangle. Tappable variants get a ripple clipped to the card's
/// own radius — never a bare `GestureDetector` on something that looks
/// pressable.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(AppSpacing.md),
    this.color,
    this.borderColor,
    this.borderRadius,
    this.showBorder = true,
    this.elevated = true,
    this.boxShadow,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;
  final BorderRadius? borderRadius;
  final bool showBorder;

  /// Set false for a card nested inside another card, where a second shadow
  /// reads as grime rather than depth.
  final bool elevated;

  /// Replaces the default soft shadow — pass [AppElevation.glow] for the rare
  /// surface meant to look lit.
  final List<BoxShadow>? boxShadow;

  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final radius = borderRadius ?? AppRadius.lgAll;
    final content = Padding(padding: padding, child: child);

    final card = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: boxShadow ?? (elevated ? AppElevation.soft(scheme) : null),
      ),
      child: Material(
        color: color ?? scheme.surfaceContainer,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: showBorder
              ? BorderSide(
                  color:
                      borderColor ?? GroovePalette.hairline(theme.brightness),
                )
              : BorderSide.none,
        ),
        child: onTap == null
            ? content
            : InkWell(onTap: onTap, borderRadius: radius, child: content),
      ),
    );

    if (semanticLabel == null) return card;
    return Semantics(
      label: semanticLabel,
      button: onTap != null,
      container: true,
      child: card,
    );
  }
}

/// A card nested inside another card — flat, tinted, no shadow. For the rows
/// and tiles that sit inside a section card.
class AppInsetCard extends StatelessWidget {
  const AppInsetCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(AppSpacing.sm),
    this.borderRadius,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AppCard(
      onTap: onTap,
      padding: padding,
      elevated: false,
      color: scheme.surfaceContainerHigh,
      borderColor: scheme.outlineVariant,
      borderRadius: borderRadius ?? AppRadius.mdAll,
      child: child,
    );
  }
}
