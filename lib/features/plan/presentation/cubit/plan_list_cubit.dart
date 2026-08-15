import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/error/failure.dart';
import '../../../../domain/repositories/plan_repository.dart';
import '../../../../domain/values/calendar_date.dart';
import 'plan_list_state.dart';

/// The Plan tab's list of programs.
///
/// Reads are a live query, so a program created in a sheet appears without
/// anyone wiring a refresh. Writes return a [Failure] instead of pushing an
/// error into the state: the list itself is still perfectly renderable when a
/// delete fails, and the right response is a snack bar, not a broken screen.
class PlanListCubit extends Cubit<PlanListState> {
  PlanListCubit({required PlanRepository repository})
    : _repository = repository,
      super(const PlanListState.loading()) {
    _subscription = _repository.watchPrograms().listen(
      (programs) => emit(PlanListState.data(programs)),
      onError: (Object error) =>
          emit(PlanListState.failure(Failure.fromException(error))),
    );
  }

  final PlanRepository _repository;
  late final StreamSubscription<void> _subscription;

  /// Returns null on success, or the failure to surface.
  Future<Failure?> createProgram({
    required String name,
    required CalendarDate startDate,
  }) async {
    final result = await _repository.createProgram(
      name: name,
      startDate: startDate,
    );
    return result.failureOrNull;
  }

  Future<Failure?> setActive(String id) async =>
      (await _repository.setActiveProgram(id)).failureOrNull;

  Future<Failure?> delete(String id) async =>
      (await _repository.deleteProgram(id)).failureOrNull;

  @override
  Future<void> close() {
    _subscription.cancel();
    return super.close();
  }
}
