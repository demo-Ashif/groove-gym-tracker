import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:groove/app/theme/app_theme.dart';
import 'package:groove/core/di/injector.dart';
import 'package:groove/core/haptics/app_haptics.dart';
import 'package:groove/domain/entities/insights.dart';
import 'package:groove/domain/enums/training_enums.dart';
import 'package:groove/domain/services/trend_service.dart';
import 'package:groove/domain/values/body_metrics.dart';
import 'package:groove/domain/values/calendar_date.dart';
import 'package:groove/features/insights/presentation/widgets/adherence_card.dart';
import 'package:groove/features/insights/presentation/widgets/weight_trend_card.dart';
import 'package:groove/l10n/generated/app_localizations.dart';

/// The cards on their own, with data — the states the page-level test cannot
/// reach without seeding a whole program.
void main() {
  // The chart ticks a selection haptic when a point is picked, and it reads
  // the app-scoped instance the toggle in Settings owns.
  setUp(() => getIt.registerSingleton<AppHaptics>(AppHaptics()));
  tearDown(resetDependencies);

  Widget harness(
    Widget child, {
    Brightness brightness = Brightness.dark,
    double scale = 1,
    Size size = const Size(360, 800),
  }) {
    return MaterialApp(
      theme: (brightness == Brightness.dark ? AppTheme.dark() : AppTheme.light())
          .copyWith(splashFactory: InkRipple.splashFactory),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: SingleChildScrollView(child: child),
        ),
      ),
    );
  }

  const stats = AdherenceStats(
    plannedSets: 48,
    completedSets: 41,
    plannedSessions: 4,
    completedSessions: 3,
  );

  const skips = SkipBreakdown({SkipReason.pain: 3, SkipReason.time: 4});

  final points = TrendService.withMovingAverage([
    for (var day = 1; day <= 12; day++)
      WeightPoint(
        date: CalendarDate(2026, 8, day),
        kg: 84 - day * 0.2,
      ),
  ]);

  testWidgets('adherence renders its ring, counts and skip reasons', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(const AdherenceCard(adherence: stats, skips: skips)),
    );
    // The ring sweeps in over 450ms; let it finish.
    await tester.pump(const Duration(milliseconds: 600));

    final l10n = await L10n.delegate.load(const Locale('en'));

    expect(find.text('85%'), findsOneWidget);
    expect(find.text(l10n.insightsAdherenceSets('41', '48')), findsOneWidget);
    // Pain is broken out rather than folded into one grey "missed" count.
    expect(find.text(l10n.skipPain), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('adherence survives 1.4x text on a narrow phone', (tester) async {
    await tester.pumpWidget(
      harness(
        const AdherenceCard(adherence: stats, skips: skips),
        brightness: Brightness.light,
        scale: 1.4,
        size: const Size(320, 800),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    expect(tester.takeException(), isNull);
  });

  testWidgets('a range with no plan shows the empty state, not a 0% ring', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        const AdherenceCard(
          adherence: AdherenceStats.empty,
          skips: SkipBreakdown.empty,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    final l10n = await L10n.delegate.load(const Locale('en'));

    expect(find.text(l10n.insightsAdherenceEmptyTitle), findsOneWidget);
    expect(find.text('0%'), findsNothing);
  });

  testWidgets('the weight card draws in and reports its change', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        WeightTrendCard(points: points, unitSystem: UnitSystem.metric),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    final l10n = await L10n.delegate.load(const Locale('en'));

    // 84.0 - 0.2 down to 81.6 over twelve days: −2.2 kg, latest 81.6 kg.
    expect(find.text(l10n.unitsKg('81.6')), findsOneWidget);
    expect(
      find.text(l10n.insightsWeightDelta('−${l10n.unitsKg('2.2')}')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('imperial deltas are pounds, not stone and pounds', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        WeightTrendCard(points: points, unitSystem: UnitSystem.imperial),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    final l10n = await L10n.delegate.load(const Locale('en'));

    // 2.2 kg is 4.9 lb — never "0 st 4.9 lb".
    expect(
      find.text(l10n.insightsWeightDelta('−${l10n.unitsLb('4.9')}')),
      findsOneWidget,
    );
  });

  testWidgets('a single weigh-in is a number, not a trend', (tester) async {
    await tester.pumpWidget(
      harness(
        WeightTrendCard(
          points: points.take(1).toList(),
          unitSystem: UnitSystem.metric,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    final l10n = await L10n.delegate.load(const Locale('en'));

    expect(find.text(l10n.insightsWeightEmptyTitle), findsOneWidget);
  });
}
