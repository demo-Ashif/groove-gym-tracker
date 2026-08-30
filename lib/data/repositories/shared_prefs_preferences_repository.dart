import 'package:shared_preferences/shared_preferences.dart';

import '../../core/error/result.dart';
import '../../domain/entities/app_preferences.dart';
import '../../domain/repositories/preferences_repository.dart';
import '../../domain/values/body_metrics.dart';

/// `shared_preferences` implementation. Non-sensitive scalars only (ADR §3) —
/// the Supabase session and any API key go to `flutter_secure_storage`.
///
/// Keys are namespaced and versioned so a future format change can migrate
/// rather than silently reset someone's theme.
class SharedPrefsPreferencesRepository implements PreferencesRepository {
  SharedPrefsPreferencesRepository(this._prefs);

  static const _themeModeKey = 'prefs.v1.themeMode';
  static const _localeKey = 'prefs.v1.locale';
  static const _hapticsKey = 'prefs.v1.haptics';
  static const _lastTabKey = 'prefs.v1.lastTab';
  static const _unitSystemKey = 'prefs.v1.unitSystem';
  static const _genderKey = 'prefs.v1.gender';
  static const _heightCmKey = 'prefs.v1.heightCm';

  final SharedPreferences _prefs;

  @override
  AppPreferences read() {
    const defaults = AppPreferences();
    return AppPreferences(
      themeMode: AppThemeMode.fromId(_prefs.getString(_themeModeKey)),
      localeCode: _prefs.getString(_localeKey),
      hapticsEnabled: _prefs.getBool(_hapticsKey) ?? defaults.hapticsEnabled,
      // Clamped on read: the tab count can shrink between releases, and a
      // stale index would otherwise throw inside the router on first frame.
      lastTabIndex: (_prefs.getInt(_lastTabKey) ?? defaults.lastTabIndex).clamp(
        0,
        100,
      ),
      // Enums are read by name and fall back rather than throwing: a value
      // written by a newer release must not brick the settings screen.
      unitSystem: _enumByName(
        UnitSystem.values,
        _prefs.getString(_unitSystemKey),
        defaults.unitSystem,
      ),
      gender: _enumByName(
        Gender.values,
        _prefs.getString(_genderKey),
        defaults.gender,
      ),
      heightCm: _prefs.getDouble(_heightCmKey),
    );
  }

  static T _enumByName<T extends Enum>(
    List<T> values,
    String? name,
    T fallback,
  ) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return fallback;
  }

  @override
  Future<Result<AppPreferences>> save(AppPreferences preferences) =>
      Result.guard(() async {
        await Future.wait([
          _prefs.setString(_themeModeKey, preferences.themeMode.name),
          if (preferences.localeCode case final code?)
            _prefs.setString(_localeKey, code)
          else
            _prefs.remove(_localeKey),
          _prefs.setBool(_hapticsKey, preferences.hapticsEnabled),
          _prefs.setInt(_lastTabKey, preferences.lastTabIndex),
          _prefs.setString(_unitSystemKey, preferences.unitSystem.name),
          _prefs.setString(_genderKey, preferences.gender.name),
          if (preferences.heightCm case final height?)
            _prefs.setDouble(_heightCmKey, height)
          else
            _prefs.remove(_heightCmKey),
        ]);
        return read();
      });
}
