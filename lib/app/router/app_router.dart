import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/extensions/context_extensions.dart';
import '../../features/active_session/presentation/pages/active_session_page.dart';
import '../../features/insights/presentation/pages/insights_page.dart';
import '../../features/plan/presentation/pages/plan_page.dart';
import '../../features/plan/presentation/pages/program_editor_page.dart';
import '../../features/plan/presentation/pages/session_editor_page.dart';
import '../../features/settings/presentation/pages/profile_page.dart';
import '../../features/today/presentation/pages/today_page.dart';
import '../../shared/widgets/state_views.dart';
import '../shell/app_shell.dart';
import 'app_routes.dart';

/// Builds the app router.
///
/// No redirect and no auth gate: Groove signs in anonymously in the
/// background (ADR §5.1) and there is no screen in front of the app. If the
/// session can't be refreshed the app degrades to offline — never to a login
/// wall (ADR §18).
///
/// The navigator key is created per call rather than held as a static, so two
/// routers can coexist (hot restart, widget tests) without colliding on the
/// same [GlobalKey].
abstract final class AppRouter {
  static GoRouter create({int initialTabIndex = 0}) {
    final rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

    return GoRouter(
      navigatorKey: rootKey,
      // Reopens the tab the user was last on, read synchronously from prefs
      // during bootstrap.
      initialLocation: AppRoutes.branchAt(initialTabIndex),
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, navigationShell) =>
              AppShell(navigationShell: navigationShell),
          branches: [
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: AppRoutes.today,
                  builder: (context, state) => const TodayPage(),
                  routes: [
                    GoRoute(
                      path: AppRoutes.activeSessionSegment,
                      parentNavigatorKey: rootKey,
                      builder: (context, state) => ActiveSessionPage(
                        scheduledSessionId:
                            state.pathParameters[AppRoutes.scheduledIdParam]!,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: AppRoutes.plan,
                  builder: (context, state) => const PlanPage(),
                  routes: [
                    GoRoute(
                      path: AppRoutes.programEditorSegment,
                      parentNavigatorKey: rootKey,
                      builder: (context, state) => ProgramEditorPage(
                        programId:
                            state.pathParameters[AppRoutes.programIdParam]!,
                      ),
                      routes: [
                        GoRoute(
                          path: AppRoutes.sessionEditorSegment,
                          parentNavigatorKey: rootKey,
                          builder: (context, state) => SessionEditorPage(
                            programId:
                                state.pathParameters[AppRoutes.programIdParam]!,
                            sessionId:
                                state.pathParameters[AppRoutes.sessionIdParam]!,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: AppRoutes.insights,
                  builder: (context, state) => const InsightsPage(),
                ),
              ],
            ),
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: AppRoutes.profile,
                  builder: (context, state) => const ProfilePage(),
                ),
              ],
            ),
          ],
        ),
      ],
      errorBuilder: (context, state) => const _RouteNotFoundPage(),
    );
  }
}

/// A designed 404 rather than go_router's debug text — an unknown deep link
/// is something a user can hit in the wild, from a stale notification or a
/// home-screen widget built by an older version.
class _RouteNotFoundPage extends StatelessWidget {
  const _RouteNotFoundPage();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      body: EmptyView(
        icon: Icons.explore_off_rounded,
        title: l10n.routeNotFoundTitle,
        actionLabel: l10n.routeNotFoundAction,
        onAction: () => context.go(AppRoutes.today),
      ),
    );
  }
}
