import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';
import '../../core/utils/extensions/context_extensions.dart';

/// Modal bottom sheet scaffold: a title, scrollable content, and one primary
/// action pinned to the bottom.
///
/// The form sheets in the builder all use this, so they share keyboard
/// behaviour and safe-area handling instead of each one rediscovering it.
class AppSheet extends StatelessWidget {
  const AppSheet({
    super.key,
    required this.title,
    required this.child,
    required this.actionLabel,
    this.onAction,
    this.secondary,
  });

  final String title;
  final Widget child;
  final String actionLabel;

  /// Null disables the action — an invalid form reads as disabled rather than
  /// letting the user press a button that does nothing.
  final VoidCallback? onAction;

  /// Optional destructive or tertiary action, shown under the primary one.
  final Widget? secondary;

  /// Opens [builder] as a modal sheet. `isScrollControlled` so a keyboard
  /// doesn't crush the content into a strip.
  static Future<T?> show<T>(
    BuildContext context, {
    required WidgetBuilder builder,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: builder,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Lifts the sheet above the keyboard rather than letting it slide
      // underneath, which is what makes a text field in a sheet usable.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.gutter,
            0,
            AppSpacing.gutter,
            AppSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Semantics(
                  header: true,
                  child: Text(title, style: context.textStyles.titleLarge),
                ),
              ),
              Flexible(child: SingleChildScrollView(child: child)),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(onPressed: onAction, child: Text(actionLabel)),
              if (secondary case final widget?) ...[
                const SizedBox(height: AppSpacing.xs),
                widget,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Yes/no confirmation. Returns true only on an explicit confirm — a
/// dismissed dialog is a no.
Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = true,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(context.l10n.commonCancel),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: destructive
              ? TextButton.styleFrom(foregroundColor: context.colors.error)
              : null,
          child: Text(confirmLabel),
        ),
      ],
    ),
  );

  return result ?? false;
}
