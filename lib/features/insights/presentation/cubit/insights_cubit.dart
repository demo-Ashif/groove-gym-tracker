import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../../core/error/failure.dart';
import '../../../../domain/entities/insights.dart';
import '../../../../domain/repositories/insights_repository.dart';
import '../../../../domain/values/insights_range.dart';

part 'insights_cubit.freezed.dart';

@freezed
sealed class InsightsState with _$InsightsState {
  const InsightsState._();

  const factory InsightsState.loading() = InsightsLoading;

  const factory InsightsState.data({
    required DateRange range,
    required AdherenceStats adherence,
    required SkipBreakdown skips,
    @Default([]) List<WeightPoint> weightTrend,
  }) = InsightsData;

  const factory InsightsState.failure(Failure failure) = InsightsFailure;
}

/// The cards on the Insights tab, for one window.
///
/// Three live queries rather than one: they read different tables at different
/// rates, and joining them in SQL would redraw the weight chart every time a
/// set was logged.
class InsightsCubit extends Cubit<InsightsState> {
  InsightsCubit({required InsightsRepository repository})
    : _repository = repository,
      super(const InsightsLoading());

  final InsightsRepository _repository;

  StreamSubscription<AdherenceStats>? _adherenceSubscription;
  StreamSubscription<SkipBreakdown>? _skipSubscription;
  StreamSubscription<List<WeightPoint>>? _weightSubscription;

  DateRange? _range;
  AdherenceStats? _adherence;
  SkipBreakdown? _skips;
  List<WeightPoint>? _weightTrend;

  /// Points every card at [range].
  ///
  /// The previous window's numbers stay on screen until the new ones land.
  /// These are local queries measured in milliseconds, and dropping back to a
  /// skeleton between two of them reads as a flicker, not as progress.
  void setRange(DateRange range) {
    if (_range == range) return;
    _range = range;

    _adherence = null;
    _skips = null;
    _weightTrend = null;

    unawaited(_adherenceSubscription?.cancel());
    unawaited(_skipSubscription?.cancel());
    unawaited(_weightSubscription?.cancel());

    _adherenceSubscription = _repository.watchAdherence(range).listen((stats) {
      _adherence = stats;
      _emit();
    }, onError: _onError);

    _skipSubscription = _repository.watchSkipBreakdown(range).listen((skips) {
      _skips = skips;
      _emit();
    }, onError: _onError);

    _weightSubscription = _repository.watchWeightTrend(range).listen((points) {
      _weightTrend = points;
      _emit();
    }, onError: _onError);
  }

  /// Re-runs the current window's queries — what the error state's retry
  /// button does. A dropped subscription is not recoverable by waiting.
  void refresh() {
    final range = _range;
    if (range == null) return;
    _range = null;
    setRange(range);
  }

  void _onError(Object error) {
    if (isClosed) return;
    emit(InsightsState.failure(Failure.fromException(error)));
  }

  void _emit() {
    if (isClosed) return;

    final range = _range;
    final adherence = _adherence;
    final skips = _skips;
    final weightTrend = _weightTrend;

    // All three or none: a card set where adherence describes this week and
    // the weight chart still describes last week is worse than a beat of
    // stillness.
    if (range == null ||
        adherence == null ||
        skips == null ||
        weightTrend == null) {
      return;
    }

    emit(
      InsightsState.data(
        range: range,
        adherence: adherence,
        skips: skips,
        weightTrend: weightTrend,
      ),
    );
  }

  @override
  Future<void> close() {
    _adherenceSubscription?.cancel();
    _skipSubscription?.cancel();
    _weightSubscription?.cancel();
    return super.close();
  }
}
