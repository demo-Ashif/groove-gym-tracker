import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../core/di/injector.dart';
import '../domain/entities/app_preferences.dart';
import '../features/settings/presentation/cubit/preferences_cubit.dart';
import '../features/settings/presentation/cubit/preferences_state.dart';
import '../l10n/generated/app_localizations.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';
import 'theme/app_tokens.dart';

/// App root. Stateful so the router is built exactly once — recreating a
/// [GoRouter] on rebuild would drop navigation state on every theme change.
class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  /// Owned by get_it (registered with `dispose:`), not by this widget — hence
  /// `BlocProvider.value` and no `close()` here.
  late final PreferencesCubit _preferences = getIt<PreferencesCubit>();

  late final GoRouter _router = AppRouter.create(
    initialTabIndex: _preferences.state.preferences.lastTabIndex,
  );

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _preferences,
      child: BlocBuilder<PreferencesCubit, PreferencesState>(
        // Only the fields `MaterialApp` itself reads should rebuild the whole
        // app. The haptics toggle and the last-tab index must not.
        buildWhen: (previous, current) =>
            previous.preferences.themeMode != current.preferences.themeMode ||
            previous.preferences.localeCode != current.preferences.localeCode,
        builder: (context, state) {
          return MaterialApp.router(
            onGenerateTitle: (context) => L10n.of(context).appTitle,
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: switch (state.preferences.themeMode) {
              AppThemeMode.system => ThemeMode.system,
              AppThemeMode.light => ThemeMode.light,
              AppThemeMode.dark => ThemeMode.dark,
            },
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            // Null follows the system (ADR §12.1).
            locale: switch (state.preferences.localeCode) {
              final code? => Locale(code),
              null => null,
            },
            routerConfig: _router,
            builder: (context, child) => _TextScaleGuard(child: child),
          );
        },
      ),
    );
  }
}

/// Clamps the user's text-size setting to 0.85–1.4 (ADR §13.3).
///
/// Below that the numerals stop being readable across a gym; above it the set
/// chips in the active-session grid break their row. Clamping rather than
/// ignoring keeps the accessibility setting meaningful — it just can't take
/// the layout apart.
class _TextScaleGuard extends StatelessWidget {
  const _TextScaleGuard({required this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);

    return MediaQuery(
      data: media.copyWith(
        textScaler: media.textScaler.clamp(
          minScaleFactor: AppSizes.minTextScale,
          maxScaleFactor: AppSizes.maxTextScale,
        ),
      ),
      // `MaterialApp.builder` can be handed a null child during a route
      // transition edge case; an empty box is the documented fallback.
      child: child ?? const SizedBox.shrink(),
    );
  }
}
