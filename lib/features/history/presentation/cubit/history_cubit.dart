import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../../core/error/failure.dart';
import '../../../../domain/entities/exercise.dart';
import '../../../../domain/entities/session_log.dart';
import '../../../../domain/repositories/exercise_repository.dart';
import '../../../../domain/repositories/log_repository.dart';

part 'history_cubit.freezed.dart';

@freezed
sealed class HistoryState with _$HistoryState {
  const HistoryState._();

  const factory HistoryState.loading() = HistoryLoading;

  const factory HistoryState.data({
    @Default([]) List<SessionHistoryEntry> sessions,

    /// The catalog, for resolving exercise names and tonnage multipliers
    /// without each row hitting the database.
    @Default({}) Map<String, Exercise> exercisesById,
  }) = HistoryData;

  const factory HistoryState.failure(Failure failure) = HistoryFailure;
}

/// Every finished session, newest first.
///
/// Two live queries rather than one: the catalog changes far less often than
/// the log, and joining them in SQL would rebuild the whole list every time an
/// exercise was renamed.
class HistoryCubit extends Cubit<HistoryState> {
  HistoryCubit({
    required LogRepository logRepository,
    required ExerciseRepository exerciseRepository,
  }) : _log = logRepository,
       _exercises = exerciseRepository,
       super(const HistoryLoading()) {
    _sessionSubscription = _log.watchFinishedSessions().listen((sessions) {
      _sessions = sessions;
      _sessionsLoaded = true;
      _emit();
    }, onError: _onError);

    _catalogSubscription = _exercises.watchCatalog().listen((exercises) {
      _catalog = {for (final exercise in exercises) exercise.id: exercise};
      _catalogLoaded = true;
      _emit();
    }, onError: _onError);
  }

  final LogRepository _log;
  final ExerciseRepository _exercises;

  late final StreamSubscription<void> _sessionSubscription;
  late final StreamSubscription<void> _catalogSubscription;

  List<SessionHistoryEntry> _sessions = const [];
  Map<String, Exercise> _catalog = const {};

  bool _sessionsLoaded = false;
  bool _catalogLoaded = false;

  void _onError(Object error) =>
      emit(HistoryState.failure(Failure.fromException(error)));

  void _emit() {
    // Both or neither: a list that renders before the catalog arrives shows a
    // column of blank exercise names, then rewrites itself.
    if (!_sessionsLoaded || !_catalogLoaded) return;

    emit(HistoryState.data(sessions: _sessions, exercisesById: _catalog));
  }

  @override
  Future<void> close() {
    _sessionSubscription.cancel();
    _catalogSubscription.cancel();
    return super.close();
  }
}
