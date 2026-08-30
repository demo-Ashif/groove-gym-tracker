import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../app/theme/app_tokens.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/utils/extensions/context_extensions.dart';
import '../../../../domain/values/calendar_date.dart';
import '../../../../domain/values/insights_range.dart';
import '../../../../shared/widgets/app_page.dart';
import '../../../../shared/widgets/page_header.dart';
import '../../../../shared/widgets/skeleton.dart';
import '../../../../shared/widgets/state_views.dart';
import '../../../settings/presentation/cubit/preferences_cubit.dart';
import '../cubit/insights_cubit.dart';
import '../cubit/insights_range_cubit.dart';
import '../widgets/adherence_card.dart';
import '../widgets/insights_range_filter.dart';
import '../widgets/weight_trend_card.dart';

/// The Insights tab — adherence and body weight over a Day/Week/Month/Cycle
/// window (ADR §11).
///
/// Stateful for one reason: the week's first day is locale data that only the
/// widget tree knows, and the range cubit has to be told rather than guess.
class InsightsPage extends StatefulWidget {
  const InsightsPage({super.key});

  @override
  State<InsightsPage> createState() => _InsightsPageState();
}

class _InsightsPageState extends State<InsightsPage> {
  /// App-scoped: switching tabs and coming back must not reset the range the
  /// user chose. Owned by the injector, so this page never closes it.
  final InsightsRangeCubit _rangeCubit = getIt<InsightsRangeCubit>();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // `firstDayOfWeekIndex` is 0 = Sunday … 6 = Saturday; the domain speaks
    // ISO, where Monday is 1 and Sunday is 7.
    final index = MaterialLocalizations.of(context).firstDayOfWeekIndex;
    _rangeCubit.setFirstDayOfWeek(index == 0 ? DateTime.sunday : index);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: _rangeCubit),
        BlocProvider<InsightsCubit>(
          // Pointed at the current window immediately, so the first frame
          // after the queries land is already the right one.
          create: (_) => getIt<InsightsCubit>()..setRange(_rangeCubit.state.range),
        ),
      ],
      child: BlocListener<InsightsRangeCubit, InsightsRangeState>(
        listenWhen: (previous, current) => previous.range != current.range,
        listener: (context, state) =>
            context.read<InsightsCubit>().setRange(state.range),
        child: AppPage(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PageHeader(l10n.insightsTitle),
              const InsightsRangeFilter(),
              const SizedBox(height: AppSpacing.sm),
              const Expanded(child: _InsightsBody()),
            ],
          ),
        ),
      ),
    );
  }
}

class _InsightsBody extends StatelessWidget {
  const _InsightsBody();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<InsightsCubit, InsightsState>(
      builder: (context, state) {
        return AnimatedSwitcher(
          duration: AppDurations.base,
          switchInCurve: AppMotion.standard,
          child: switch (state) {
            InsightsLoading() => const _InsightsSkeleton(
              key: ValueKey('loading'),
            ),
            InsightsFailure(:final failure) => ErrorView(
              key: const ValueKey('error'),
              failure: failure,
              onRetry: context.read<InsightsCubit>().refresh,
            ),
            InsightsData() => _InsightsCards(
              key: const ValueKey('data'),
              state: state,
            ),
          },
        );
      },
    );
  }
}

class _InsightsCards extends StatelessWidget {
  const _InsightsCards({super.key, required this.state});

  final InsightsData state;

  @override
  Widget build(BuildContext context) {
    final unitSystem = context
        .watch<PreferencesCubit>()
        .state
        .preferences
        .unitSystem;

    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      children: [
        AdherenceCard(adherence: state.adherence, skips: state.skips),
        const SizedBox(height: AppSpacing.sm),
        BlocSelector<InsightsRangeCubit, InsightsRangeState, List<CalendarDate>>(
          // Only the phase starts matter here, so the card is spared a rebuild
          // every time the anchor moves inside the same program.
          selector: _phaseBoundaries,
          builder: (context, boundaries) => WeightTrendCard(
            points: state.weightTrend,
            unitSystem: unitSystem,
            phaseBoundaries: boundaries,
          ),
        ),
      ],
    );
  }

  static List<CalendarDate> _phaseBoundaries(InsightsRangeState state) {
    final program = state.program;
    if (program == null) return const [];

    return [
      for (final phase in program.phases)
        ?InsightsWindow.phase(program, phase).start,
    ];
  }
}

/// A skeleton shaped like the cards it replaces, so nothing jumps when the
/// real numbers land (ADR §13.6).
class _InsightsSkeleton extends StatelessWidget {
  const _InsightsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    // A list, not a column: the skeleton stands in for scrolling content, and
    // a fixed-height column overflows the moment the cards are taller than the
    // viewport — which is exactly what happens at large text scales.
    return Shimmer(
      child: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xl),
        children: const [
          SkeletonCard(height: 172),
          SizedBox(height: AppSpacing.sm),
          SkeletonCard(height: 268),
        ],
      ),
    );
  }
}
