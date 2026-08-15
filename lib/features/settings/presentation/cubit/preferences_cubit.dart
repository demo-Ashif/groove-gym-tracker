import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/haptics/app_haptics.dart';
import '../../../../domain/entities/app_preferences.dart';
import '../../../../domain/repositories/preferences_repository.dart';
import 'preferences_state.dart';

/// App-scoped. `MaterialApp` rebuilds off this, so a theme or language change
/// applies instantly to every surface including the system bars.
///
/// Writes are optimistic: the UI flips immediately and reconciles with what
/// the store actually persisted. A settings toggle that waits on I/O before
/// moving feels broken. A failed write rolls the value back rather than
/// leaving the UI claiming a preference that isn't stored.
class PreferencesCubit extends Cubit<PreferencesState> {
  PreferencesCubit({
    required PreferencesRepository repository,
    required AppHaptics haptics,
  }) : _repository = repository,
       _haptics = haptics,
       super(PreferencesState(preferences: repository.read())) {
    // The store is the source of truth for the toggle; push its current value
    // into the service that acts on it.
    _haptics.enabled = state.preferences.hapticsEnabled;
  }

  final PreferencesRepository _repository;
  final AppHaptics _haptics;

  Future<void> setThemeMode(AppThemeMode mode) =>
      _update(state.preferences.copyWith(themeMode: mode));

  /// [code] null means "follow the system" (ADR §12.1).
  Future<void> setLocale(String? code) => _update(
    state.preferences.copyWith(localeCode: code, clearLocaleCode: code == null),
  );

  Future<void> setHapticsEnabled({required bool enabled}) {
    // Applied before the write so the confirming tick fires immediately —
    // and, when switching off, so no tick fires at all.
    _haptics.enabled = enabled;
    return _update(state.preferences.copyWith(hapticsEnabled: enabled));
  }

  /// Persisted so a cold start reopens the tab the user was last on.
  Future<void> setLastTabIndex(int index) {
    if (index == state.preferences.lastTabIndex) return Future<void>.value();
    return _update(state.preferences.copyWith(lastTabIndex: index));
  }

  Future<void> _update(AppPreferences preferences) async {
    final previous = state.preferences;
    emit(PreferencesState(preferences: preferences));

    final result = await _repository.save(preferences);
    if (isClosed) return;

    emit(
      result.fold((saved) => PreferencesState(preferences: saved), (failure) {
        _haptics.enabled = previous.hapticsEnabled;
        return PreferencesState(preferences: previous, saveFailure: failure);
      }),
    );
  }
}
