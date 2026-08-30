import 'package:flutter/material.dart';

import '../../app/theme/app_tokens.dart';
import '../../core/error/failure.dart';
import '../../core/utils/extensions/context_extensions.dart';

/// Every list and chart ships three designed states (ADR §13.6). They live in
/// one file because they share a layout — the same icon size, the same
/// rhythm, the same action placement — and keeping them together is what stops
/// them drifting apart.

/// Empty: an icon, one honest line of why, and one clear action. Never a
/// blank screen.
class EmptyView extends StatelessWidget {
  const EmptyView({
    super.key,
    this.title,
    this.message,
    this.icon = Icons.inbox_outlined,
    this.actionLabel,
    this.onAction,
  });

  /// Falls back to a generic line, but a screen should nearly always pass its
  /// own — "No program yet" tells the user something; "Nothing here yet"
  /// doesn't.
  final String? title;
  final String? message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return _StateScaffold(
      icon: icon,
      iconColor: context.colors.onSurfaceVariant,
      iconBackground: context.colors.surfaceContainerHigh,
      title: title ?? context.l10n.stateEmptyTitle,
      message: message,
      action: (actionLabel != null && onAction != null)
          ? FilledButton(onPressed: onAction, child: Text(actionLabel!))
          : null,
    );
  }
}

/// Error: what happened, plus retry. The copy is resolved from the failure's
/// *type* — domain failures carry a kind, never an English sentence
/// (ADR §12.2 rule 1).
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.failure, this.onRetry});

  final Failure failure;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isOffline = failure is NetworkFailure;

    final (title, message) = switch (failure) {
      NetworkFailure() => (l10n.stateOfflineTitle, l10n.stateOfflineBody),
      StorageFailure() => (l10n.stateErrorTitle, l10n.stateStorageBody),
      AuthFailure() => (l10n.stateErrorTitle, l10n.stateAuthBody),
      ParseFailure() => (l10n.stateErrorTitle, l10n.stateParseBody),
      ServerFailure() ||
      ValidationFailure() ||
      UnexpectedFailure() => (l10n.stateErrorTitle, l10n.stateErrorBody),
    };

    return _StateScaffold(
      icon: isOffline ? Icons.wifi_off_rounded : Icons.error_outline_rounded,
      // Offline is an expected state in a gym, not a fault — it reads in the
      // neutral tone. A real error gets the error colour.
      iconColor: isOffline
          ? context.colors.onSurfaceVariant
          : context.colors.error,
      iconBackground: isOffline
          ? context.colors.surfaceContainerHigh
          : context.colors.errorContainer,
      title: title,
      message: message,
      action: onRetry == null
          ? null
          : OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(l10n.commonRetry),
            ),
    );
  }
}

/// Indeterminate wait with no content shape to imitate. Prefer a skeleton
/// (`Skeleton*` in `skeleton.dart`) wherever the shape of the result is
/// known — this is the fallback, not the default.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox.square(
            dimension: 28,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          if (label case final text?) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              text,
              style: context.textStyles.bodyMedium?.copyWith(
                color: context.colors.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

/// Shared layout for the three states above, so they are visually one family.
class _StateScaffold extends StatelessWidget {
  const _StateScaffold({
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.title,
    this.message,
    this.action,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: SingleChildScrollView(
        // Scrollable so the state survives a short landscape window at 1.4×
        // text scale instead of overflowing.
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: iconBackground,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 30, color: iconColor),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                title,
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              if (message case final text?) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              if (action case final widget?) ...[
                const SizedBox(height: AppSpacing.lg),
                widget,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
