import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/backup/backup_service.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/exercise_repository_impl.dart';
import '../../data/repositories/check_in_repository_impl.dart';
import '../../data/repositories/log_repository_impl.dart';
import '../../data/repositories/plan_repository_impl.dart';
import '../../data/repositories/schedule_repository_impl.dart';
import '../../data/repositories/shared_prefs_preferences_repository.dart';
import '../../domain/repositories/exercise_repository.dart';
import '../../domain/repositories/check_in_repository.dart';
import '../../domain/repositories/log_repository.dart';
import '../../domain/repositories/plan_repository.dart';
import '../../domain/repositories/preferences_repository.dart';
import '../../domain/repositories/schedule_repository.dart';
import '../../features/active_session/presentation/cubit/active_session_cubit.dart';
import '../../features/history/presentation/cubit/history_cubit.dart';
import '../../features/history/presentation/cubit/session_detail_cubit.dart';
import '../../features/plan/presentation/cubit/plan_list_cubit.dart';
import '../../features/plan/presentation/cubit/program_editor_cubit.dart';
import '../../features/plan/presentation/cubit/session_editor_cubit.dart';
import '../../features/today/presentation/cubit/today_cubit.dart';
import '../../features/settings/presentation/cubit/preferences_cubit.dart';
import '../config/app_config.dart';
import '../config/app_env.dart';
import '../haptics/app_haptics.dart';

final getIt = GetIt.instance;

/// Registers dependencies.
///
/// Almost everything is lazy, so this returns in microseconds and never
/// blocks the first frame. The one exception is [SharedPreferences]: opening
/// it is a local plist/XML read, and having it resolved *before* `runApp`
/// means the theme, the language and the tab to open are all known for the
/// first frame. Loading them asynchronously afterwards is what produces the
/// light-theme flash on cold start.
///
/// Scoping rules:
/// - `registerLazySingleton` — app-scoped services. Pass `dispose:` when the
///   object owns resources.
/// - `registerFactory` — screen-scoped cubits, owned and closed by the
///   widget tree's `BlocProvider`.
Future<void> configureDependencies(
  AppEnvironment env, {
  AppDatabase? database,
}) async {
  final prefs = await SharedPreferences.getInstance();

  getIt
    ..registerSingleton<AppConfig>(AppConfig.fromEnv(env))
    ..registerSingleton<SharedPreferences>(prefs)
    // Lazy on purpose: opening SQLite, running the migration and seeding 122
    // catalog rows all happen on first query, behind the first frame, on
    // drift's background isolate. `database` is the seam for tests, which
    // pass an in-memory executor.
    ..registerLazySingleton<AppDatabase>(
      () => database ?? AppDatabase(),
      dispose: (db) => db.close(),
    )
    ..registerLazySingleton<ExerciseRepository>(
      () => ExerciseRepositoryImpl(getIt<AppDatabase>().exerciseDao),
    )
    ..registerLazySingleton<PlanRepository>(
      () => PlanRepositoryImpl(getIt<AppDatabase>().planDao),
    )
    ..registerLazySingleton<BackupService>(
      () => BackupService(getIt<AppDatabase>()),
    )
    ..registerLazySingleton<LogRepository>(
      () => LogRepositoryImpl(getIt<AppDatabase>().logDao),
    )
    ..registerLazySingleton<CheckInRepository>(
      () => CheckInRepositoryImpl(getIt<AppDatabase>().checkInDao),
    )
    ..registerLazySingleton<ScheduleRepository>(
      () => ScheduleRepositoryImpl(
        dao: getIt<AppDatabase>().scheduleDao,
        planRepository: getIt(),
      ),
    )
    ..registerLazySingleton<AppHaptics>(AppHaptics.new)
    ..registerLazySingleton<PreferencesRepository>(
      () => SharedPrefsPreferencesRepository(getIt()),
    )
    // App-scoped: `MaterialApp` rebuilds off this, so there is exactly one.
    ..registerLazySingleton<PreferencesCubit>(
      () => PreferencesCubit(repository: getIt(), haptics: getIt()),
      dispose: (cubit) => cubit.close(),
    )
    // Screen-scoped: each page's `BlocProvider` owns and closes these, which
    // is also what cancels their database subscriptions.
    ..registerFactory<PlanListCubit>(() => PlanListCubit(repository: getIt()))
    ..registerFactory<TodayCubit>(
      () => TodayCubit(
        planRepository: getIt(),
        scheduleRepository: getIt(),
        logRepository: getIt(),
        checkInRepository: getIt(),
      ),
    )
    ..registerFactoryParam<ActiveSessionCubit, String, void>(
      (scheduledSessionId, _) => ActiveSessionCubit(
        logRepository: getIt(),
        planRepository: getIt(),
        scheduleRepository: getIt(),
        exerciseRepository: getIt(),
        scheduledSessionId: scheduledSessionId,
      ),
    )
    ..registerFactory<HistoryCubit>(
      () => HistoryCubit(logRepository: getIt(), exerciseRepository: getIt()),
    )
    ..registerFactoryParam<SessionDetailCubit, String, void>(
      (sessionLogId, _) => SessionDetailCubit(
        logRepository: getIt(),
        exerciseRepository: getIt(),
        sessionLogId: sessionLogId,
      ),
    )
    ..registerFactoryParam<ProgramEditorCubit, String, void>(
      (programId, _) => ProgramEditorCubit(
        repository: getIt(),
        scheduleRepository: getIt(),
        programId: programId,
      ),
    )
    ..registerFactoryParam<SessionEditorCubit, String, String>(
      (programId, sessionId) => SessionEditorCubit(
        planRepository: getIt(),
        exerciseRepository: getIt(),
        programId: programId,
        sessionId: sessionId,
      ),
    );
}

/// Tears the graph down. For tests, and for a hot-restart-safe re-bootstrap.
Future<void> resetDependencies() => getIt.reset();
