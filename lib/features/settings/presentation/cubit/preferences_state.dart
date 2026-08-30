import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../../core/error/failure.dart';
import '../../../../domain/entities/app_preferences.dart';

part 'preferences_state.freezed.dart';

/// Preferences always have a renderable value — they are read synchronously
/// during `bootstrap()` and the app is themed from them before the first
/// frame — so there is no loading branch to model. A single state class with
/// an optional [saveFailure] is the honest shape.
@freezed
abstract class PreferencesState with _$PreferencesState {
  const factory PreferencesState({
    required AppPreferences preferences,

    /// Set when a write failed and the UI was rolled back, so a screen can
    /// surface it. Cleared on the next successful write.
    Failure? saveFailure,
  }) = _PreferencesState;
}
