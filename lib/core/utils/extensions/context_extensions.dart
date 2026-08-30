import 'package:flutter/material.dart';

import '../../../app/theme/app_semantic_colors.dart';
import '../../../l10n/generated/app_localizations.dart';

/// Shorthand for the four things nearly every widget reaches for.
extension ThemeContext on BuildContext {
  ThemeData get theme => Theme.of(this);
  ColorScheme get colors => theme.colorScheme;
  TextTheme get textStyles => theme.textTheme;

  /// Success / warning / info, which the M3 [ColorScheme] has no slot for.
  AppSemanticColors get semanticColors => AppSemanticColors.from(this);

  /// Localized strings. `L10n.of(context)` is non-nullable — see
  /// `l10n.yaml`'s `nullable-getter: false`.
  L10n get l10n => L10n.of(this);

  bool get isDarkMode => theme.brightness == Brightness.dark;

  EdgeInsets get viewPadding => MediaQuery.viewPaddingOf(this);

  void hideKeyboard() => FocusScope.of(this).unfocus();

  void showSnackBar(String message, {bool isError = false}) {
    final messenger = ScaffoldMessenger.of(this);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            // The themed content style is `onInverseSurface`, which would be
            // unreadable on the error container — so the error variant states
            // its own pair.
            style: isError
                ? textStyles.bodyMedium?.copyWith(
                    color: colors.onErrorContainer,
                  )
                : null,
          ),
          backgroundColor: isError ? colors.errorContainer : null,
          showCloseIcon: isError,
          closeIconColor: isError ? colors.onErrorContainer : null,
        ),
      );
  }
}
