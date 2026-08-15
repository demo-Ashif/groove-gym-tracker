import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/di/injector.dart';
import '../../core/haptics/app_haptics.dart';
import '../../core/utils/extensions/context_extensions.dart';
import '../../features/settings/presentation/cubit/preferences_cubit.dart';
import '../../l10n/generated/app_localizations.dart';
import '../theme/app_theme.dart';
import '../theme/groove_palette.dart';

/// The four-tab shell (ADR §13.5): Today · Plan · Insights · Profile.
///
/// Backed by `StatefulShellRoute.indexedStack`, so each tab keeps its own
/// navigation stack and scroll position — opening Insights and coming back
/// doesn't reset where you were.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  void _onDestinationSelected(BuildContext context, int index) {
    // Tick on tab change: the selection indicator slides, and the haptic
    // makes the switch feel like it landed (ADR §14.3 — never alone).
    getIt<AppHaptics>().selection();

    navigationShell.goBranch(
      index,
      // Tapping the tab you're already on pops that branch back to its root —
      // the standard "tap twice to get home" behaviour.
      initialLocation: index == navigationShell.currentIndex,
    );

    // Persisted so a cold start reopens where the user left off. Deliberately
    // not awaited — navigation must not wait on a preference write, and the
    // cubit already folds a failed write into its own state rather than
    // throwing.
    unawaited(context.read<PreferencesCubit>().setLastTabIndex(index));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;

    // No tab page uses an `AppBar`, so nothing else owns the system bar
    // style — without this the status-bar icons keep whatever the previous
    // theme set and become unreadable after a light/dark switch.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppTheme.overlayStyle(theme.brightness),
      child: Scaffold(
        body: navigationShell,
        bottomNavigationBar: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainer,
            border: Border(
              top: BorderSide(color: GroovePalette.hairline(theme.brightness)),
            ),
          ),
          child: NavigationBar(
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: (index) =>
                _onDestinationSelected(context, index),
            destinations: [
              for (final destination in _destinations)
                NavigationDestination(
                  label: destination.label(l10n),
                  tooltip: destination.label(l10n),
                  icon: Icon(destination.icon),
                  selectedIcon: Icon(destination.selectedIcon),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Order must match `AppRoutes.branches`.
  static const _destinations = [
    _Destination(
      label: _todayLabel,
      icon: Icons.today_outlined,
      selectedIcon: Icons.today_rounded,
    ),
    _Destination(
      label: _planLabel,
      icon: Icons.calendar_month_outlined,
      selectedIcon: Icons.calendar_month_rounded,
    ),
    _Destination(
      label: _insightsLabel,
      icon: Icons.show_chart_outlined,
      selectedIcon: Icons.show_chart_rounded,
    ),
    _Destination(
      label: _profileLabel,
      icon: Icons.person_outline_rounded,
      selectedIcon: Icons.person_rounded,
    ),
  ];
}

// Top-level functions rather than closures, so `_destinations` can stay
// `const` and the list isn't rebuilt on every frame.
String _todayLabel(L10n l10n) => l10n.navToday;
String _planLabel(L10n l10n) => l10n.navPlan;
String _insightsLabel(L10n l10n) => l10n.navInsights;
String _profileLabel(L10n l10n) => l10n.navProfile;

@immutable
class _Destination {
  const _Destination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  /// Resolved at build time, not stored — the label has to follow a language
  /// change without the shell being rebuilt from scratch.
  final String Function(L10n l10n) label;
  final IconData icon;
  final IconData selectedIcon;
}
