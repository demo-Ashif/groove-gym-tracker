import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:groove/core/error/failure.dart';
import 'package:groove/core/error/result.dart';
import 'package:groove/core/haptics/app_haptics.dart';
import 'package:groove/domain/entities/app_preferences.dart';
import 'package:groove/domain/repositories/preferences_repository.dart';
import 'package:groove/features/settings/presentation/cubit/preferences_cubit.dart';
import 'package:groove/features/settings/presentation/cubit/preferences_state.dart';

/// In-memory store with a switch for making the next write fail — the
/// interesting path, because a failed write has to roll the UI back rather
/// than leave it claiming a preference that was never stored.
class _FakePreferencesRepository implements PreferencesRepository {
  _FakePreferencesRepository([this._stored = const AppPreferences()]);

  AppPreferences _stored;
  bool failNextSave = false;

  @override
  AppPreferences read() => _stored;

  @override
  Future<Result<AppPreferences>> save(AppPreferences preferences) async {
    if (failNextSave) {
      failNextSave = false;
      return const Err(StorageFailure());
    }
    _stored = preferences;
    return Success(_stored);
  }
}

void main() {
  late _FakePreferencesRepository repository;
  late AppHaptics haptics;

  setUp(() {
    repository = _FakePreferencesRepository();
    haptics = AppHaptics();
  });

  test('seeds itself from the store synchronously, so the first frame is '
      'already themed', () {
    repository = _FakePreferencesRepository(
      const AppPreferences(themeMode: AppThemeMode.dark, lastTabIndex: 2),
    );

    final cubit = PreferencesCubit(repository: repository, haptics: haptics);

    expect(cubit.state.preferences.themeMode, AppThemeMode.dark);
    expect(cubit.state.preferences.lastTabIndex, 2);
    addTearDown(cubit.close);
  });

  blocTest<PreferencesCubit, PreferencesState>(
    'applies a theme change optimistically, then confirms it',
    build: () => PreferencesCubit(repository: repository, haptics: haptics),
    act: (cubit) => cubit.setThemeMode(AppThemeMode.dark),
    // One state, not two: the optimistic emit and the confirming emit are
    // equal, and `Cubit` drops a duplicate. That is the point of the
    // optimistic path — a successful write costs the UI nothing.
    expect: () => [
      const PreferencesState(
        preferences: AppPreferences(themeMode: AppThemeMode.dark),
      ),
    ],
    verify: (_) => expect(repository.read().themeMode, AppThemeMode.dark),
  );

  blocTest<PreferencesCubit, PreferencesState>(
    'rolls back and reports when the write fails',
    build: () {
      repository.failNextSave = true;
      return PreferencesCubit(repository: repository, haptics: haptics);
    },
    act: (cubit) => cubit.setThemeMode(AppThemeMode.dark),
    expect: () => [
      const PreferencesState(
        preferences: AppPreferences(themeMode: AppThemeMode.dark),
      ),
      const PreferencesState(
        preferences: AppPreferences(),
        saveFailure: StorageFailure(),
      ),
    ],
    verify: (_) => expect(repository.read().themeMode, AppThemeMode.system),
  );

  blocTest<PreferencesCubit, PreferencesState>(
    'clearing the locale override means follow the system',
    build: () => PreferencesCubit(repository: repository, haptics: haptics),
    act: (cubit) async {
      await cubit.setLocale('bn');
      await cubit.setLocale(null);
    },
    // Skips the intermediate `bn` state; what matters is that clearing it
    // lands back on a null code rather than the string 'null' or the previous
    // value.
    skip: 1,
    expect: () => [const PreferencesState(preferences: AppPreferences())],
  );

  blocTest<PreferencesCubit, PreferencesState>(
    'a no-op tab write emits nothing',
    build: () => PreferencesCubit(repository: repository, haptics: haptics),
    act: (cubit) => cubit.setLastTabIndex(0),
    expect: () => <PreferencesState>[],
  );

  test('the haptics toggle reaches the service that acts on it', () async {
    final cubit = PreferencesCubit(repository: repository, haptics: haptics);
    addTearDown(cubit.close);

    expect(haptics.enabled, isTrue);

    await cubit.setHapticsEnabled(enabled: false);
    expect(haptics.enabled, isFalse);
  });

  test('a failed haptics write restores the service state too', () async {
    final cubit = PreferencesCubit(repository: repository, haptics: haptics);
    addTearDown(cubit.close);

    repository.failNextSave = true;
    await cubit.setHapticsEnabled(enabled: false);

    expect(cubit.state.preferences.hapticsEnabled, isTrue);
    expect(haptics.enabled, isTrue);
  });
}
