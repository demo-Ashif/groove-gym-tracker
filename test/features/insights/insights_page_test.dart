import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:groove/app/theme/app_theme.dart';
import 'package:groove/core/config/app_env.dart';
import 'package:groove/core/di/injector.dart';
import 'package:groove/data/db/app_database.dart';
import 'package:groove/domain/repositories/check_in_repository.dart';
import 'package:groove/domain/values/calendar_date.dart';
import 'package:groove/features/insights/presentation/pages/insights_page.dart';
import 'package:groove/features/settings/presentation/cubit/preferences_cubit.dart';
import 'package:groove/features/insights/presentation/widgets/weight_trend_chart.dart';
import 'package:groove/l10n/generated/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Renders the tab the way the app does — real DI, real database, real
/// localizations. A chart is a `CustomPainter`, and the only way to know it
/// lays out and paints across themes and text scales is to draw it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await configureDependencies(
      AppEnvironment.dev,
      database: AppDatabase.withExecutor(NativeDatabase.memory()),
    );
  });

  tearDown(resetDependencies);

  /// Advances frames without waiting for quiescence.
  ///
  /// `pumpAndSettle` cannot be used on this screen: the loading state is a
  /// shimmer, which by design animates forever, so "settled" never arrives
  /// while a query is still in flight.
  Future<void> pumpFrames(WidgetTester tester) async {
    for (var i = 0; i < 24; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Tears the tree down inside the test body.
  ///
  /// drift cancels a query subscription asynchronously and schedules a
  /// zero-duration timer to close its stream store. Left to the framework's
  /// own teardown that timer is still pending when the test ends, which fails
  /// as "a timer is still pending" — a testing artifact, not a leak.
  Future<void> disposeTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    // Cancellation completes over a couple of microtask turns before the
    // close timer is scheduled, so one frame is not enough to drain it.
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 1));
    }
  }

  Widget harness({Brightness brightness = Brightness.dark, double scale = 1}) {
    // The app provides preferences at its root, which is where the unit
    // system every body-weight number is rendered in comes from.
    return BlocProvider.value(
      value: getIt<PreferencesCubit>(),
      child: MaterialApp(
        // Material 3's default ink sparkle is a fragment shader, and the test
        // engine cannot decode it — tapping anything would throw for reasons
        // that have nothing to do with this screen. The ripple is still an
        // ink splash, just the non-shader one.
        theme:
            (brightness == Brightness.dark
                    ? AppTheme.dark()
                    : AppTheme.light())
                .copyWith(splashFactory: InkRipple.splashFactory),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: const Scaffold(body: InsightsPage()),
        ),
      ),
    );
  }

  testWidgets('renders designed empty states before there is any data', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await pumpFrames(tester);

    final l10n = await L10n.delegate.load(const Locale('en'));

    expect(find.text(l10n.insightsTitle), findsOneWidget);
    // Both cards say why they are empty and offer one way out — never a blank
    // rectangle (ADR §13.6).
    expect(find.text(l10n.insightsAdherenceEmptyTitle), findsOneWidget);
    expect(find.text(l10n.insightsWeightEmptyTitle), findsOneWidget);
    expect(find.text(l10n.insightsAdherenceOpenPlan), findsOneWidget);

    await disposeTree(tester);
  });

  testWidgets('draws the weight trend once there are two weigh-ins', (
    tester,
  ) async {
    final checkIns = getIt<CheckInRepository>();
    // Inside the default window, which is the week containing today.
    final today = CalendarDate.today();
    await checkIns.record(date: today.addDays(-2), weightKg: 84);
    await checkIns.record(date: today, weightKg: 83.2);

    await tester.pumpWidget(harness());
    await pumpFrames(tester);

    expect(find.byType(WeightTrendChart), findsOneWidget);

    // Touching the chart pins a tooltip; it must not throw off the end of the
    // series or leave the frame.
    await tester.tapAt(tester.getCenter(find.byType(WeightTrendChart)));
    await pumpFrames(tester);

    expect(tester.takeException(), isNull);

    await disposeTree(tester);
  });

  testWidgets('holds up in light mode at 1.4x text scale', (tester) async {
    await tester.pumpWidget(
      harness(brightness: Brightness.light, scale: 1.4),
    );
    await pumpFrames(tester);

    // No overflow, no exception — the largest supported type on the narrowest
    // supported phone.
    expect(tester.takeException(), isNull);

    await disposeTree(tester);
  });

  testWidgets('switching the range keeps the tab rendered', (tester) async {
    await tester.pumpWidget(harness());
    await pumpFrames(tester);

    final l10n = await L10n.delegate.load(const Locale('en'));

    await tester.tap(find.text(l10n.insightsRangeAll));
    await pumpFrames(tester);

    expect(find.text(l10n.insightsRangeAllLabel), findsOneWidget);
    expect(tester.takeException(), isNull);

    await disposeTree(tester);
  });
}
