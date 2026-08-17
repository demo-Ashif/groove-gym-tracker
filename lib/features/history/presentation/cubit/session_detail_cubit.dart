import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../../core/error/failure.dart';
import '../../../../domain/entities/exercise.dart';
import '../../../../domain/entities/session_log.dart';
import '../../../../domain/repositories/exercise_repository.dart';
import '../../../../domain/repositories/log_repository.dart';

part 'session_detail_cubit.freezed.dart';

@freezed
sealed class SessionDetailState with _$SessionDetailState {
  const SessionDetailState._();

  const factory SessionDetailState.loading() = SessionDetailLoading;

  const factory SessionDetailState.data({
    required SessionLog log,
    @Default({}) Map<String, Exercise> exercisesById,
  }) = SessionDetailData;

  /// The log is gone — a stale deep link, or a session discarded from another
  /// screen while this one was open.
  const factory SessionDetailState.missing() = SessionDetailMissing;

  const factory SessionDetailState.failure(Failure failure) =
      SessionDetailFailure;
}

/// One finished session, in full.
class SessionDetailCubit extends Cubit<SessionDetailState> {
  SessionDetailCubit({
    required LogRepository logRepository,
    required ExerciseRepository exerciseRepository,
    required String sessionLogId,
  }) : _log = logRepository,
       _exercises = exerciseRepository,
       super(const SessionDetailLoading()) {
    _logSubscription = _log.watchSession(sessionLogId).listen((log) {
      _session = log;
      _logLoaded = true;
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

  late final StreamSubscription<void> _logSubscription;
  late final StreamSubscription<void> _catalogSubscription;

  SessionLog? _session;
  Map<String, Exercise> _catalog = const {};

  bool _logLoaded = false;
  bool _catalogLoaded = false;

  void _onError(Object error) =>
      emit(SessionDetailState.failure(Failure.fromException(error)));

  void _emit() {
    if (!_logLoaded || !_catalogLoaded) return;

    final session = _session;
    if (session == null) {
      emit(const SessionDetailMissing());
      return;
    }

    emit(SessionDetailState.data(log: session, exercisesById: _catalog));
  }

  @override
  Future<void> close() {
    _logSubscription.cancel();
    _catalogSubscription.cancel();
    return super.close();
  }
}
