import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../../core/error/failure.dart';
import '../../../../domain/entities/plan.dart';

part 'plan_list_state.freezed.dart';

/// Loading / data / error, modelled explicitly rather than as loose booleans
/// so the screen has to render all three.
///
/// There is no separate "empty" branch: an empty list is data, and the page
/// decides how to draw it.
@freezed
sealed class PlanListState with _$PlanListState {
  const factory PlanListState.loading() = PlanListLoading;

  const factory PlanListState.data(List<Program> programs) = PlanListData;

  const factory PlanListState.failure(Failure failure) = PlanListFailure;
}
