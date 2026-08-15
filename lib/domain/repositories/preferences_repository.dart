import '../../core/error/result.dart';
import '../entities/app_preferences.dart';

/// Device-local preference store.
///
/// [read] is deliberately **synchronous**. The theme, the locale and the tab
/// to open are all needed to build the very first frame, and an async load
/// there is what produces the light-theme flash on cold start. The backing
/// store is opened once during `bootstrap()`, before `runApp`, so by the time
/// anything calls this the values are already in memory.
abstract interface class PreferencesRepository {
  AppPreferences read();

  /// Returns what was actually persisted, so callers render stored state
  /// rather than what they optimistically sent.
  Future<Result<AppPreferences>> save(AppPreferences preferences);
}
