/// Typed route table — no stringly-typed paths scattered through widgets
/// (ADR §13.5). Navigate with `context.go(AppRoutes.today)`.
///
/// Paths are added here as their screens land, so this list is always the
/// truth about what the app can actually reach. The modal routes the ADR
/// calls for — active session, plan import review, check-in — are deliberately
/// absent until those screens exist; a route to a page that isn't built is a
/// deep link that crashes.
abstract final class AppRoutes {
  // --- Bottom-nav branches (ADR §13.5) -------------------------------------
  static const today = '/today';
  static const plan = '/plan';
  static const insights = '/insights';
  static const profile = '/profile';

  /// Tab order in the bottom bar. The shell maps a branch index to these, so
  /// reordering the nav is a one-line change here.
  static const branches = [today, plan, insights, profile];

  /// Clamped, because the persisted "last tab" index outlives the release
  /// that wrote it — a tab removed in a later version must not throw on
  /// startup.
  static String branchAt(int index) =>
      branches[index.clamp(0, branches.length - 1)];

  // --- plan builder --------------------------------------------------------
  // Children of /plan for URL hierarchy, but rendered on the root navigator so
  // they cover the bottom bar — editing a program is a task, not a tab.

  static String programEditor(String programId) => '$plan/$programId';

  static String sessionEditor(String programId, String sessionId) =>
      '$plan/$programId/session/$sessionId';

  /// Relative segments, as go_router wants them on child routes. Paired with
  /// the builders above so both stay in step.
  static const programEditorSegment = ':programId';
  static const sessionEditorSegment = 'session/:sessionId';

  static const programIdParam = 'programId';
  static const sessionIdParam = 'sessionId';

  // --- logging -------------------------------------------------------------
  /// The active session. A full-screen task over the shell, not a tab.
  static String activeSession(String scheduledSessionId) =>
      '$today/session/$scheduledSessionId';

  static const activeSessionSegment = 'session/:scheduledId';
  static const scheduledIdParam = 'scheduledId';
}
