import 'package:flutter_test/flutter_test.dart';
import 'package:groove/domain/entities/exercise.dart';
import 'package:groove/domain/entities/plan.dart';
import 'package:groove/domain/entities/session_log.dart';
import 'package:groove/domain/enums/training_enums.dart';
import 'package:groove/domain/services/metrics_service.dart';

/// These feed every chart in the app. A wrong multiplier here is invisible
/// until months of history have been drawn from it, which is why the awkward
/// combinations are spelled out rather than assumed.
void main() {
  Exercise exercise({
    LoadType loadType = LoadType.barbell,
    bool unilateral = false,
  }) => Exercise(
    id: 'ex-1',
    nameKey: 'exBackSquat',
    pattern: MovementPattern.squat,
    bodySection: BodySection.legs,
    loadType: loadType,
    isUnilateral: unilateral,
  );

  SetLog set({
    double? weightKg = 100,
    int? reps = 5,
    SetStatus status = SetStatus.done,
    SetSide side = SetSide.both,
    SkipReason? skipReason,
    int index = 0,
  }) => SetLog(
    id: 'set-$index',
    sessionLogId: 'log-1',
    exerciseId: 'ex-1',
    setIndex: index,
    weightKg: weightKg,
    reps: reps,
    status: status,
    side: side,
    skipReason: skipReason,
  );

  group('e1RM', () {
    test('applies Epley', () {
      // 100 × (1 + 5/30) = 116.67
      expect(
        MetricsService.e1rm(weightKg: 100, reps: 5, loadType: LoadType.barbell),
        closeTo(116.67, 0.01),
      );
    });

    test('a single is the weight itself', () {
      expect(
        MetricsService.e1rm(weightKg: 140, reps: 1, loadType: LoadType.barbell),
        closeTo(144.67, 0.01),
      );
    });

    test('refuses above 12 reps, where Epley stops resembling reality', () {
      expect(
        MetricsService.e1rm(weightKg: 60, reps: 12, loadType: LoadType.barbell),
        isNotNull,
      );
      expect(
        MetricsService.e1rm(weightKg: 60, reps: 13, loadType: LoadType.barbell),
        isNull,
      );
    });

    test('refuses load types with nothing to extrapolate from', () {
      for (final loadType in [
        LoadType.bodyweight,
        LoadType.band,
        LoadType.time,
        LoadType.distance,
      ]) {
        expect(
          MetricsService.e1rm(weightKg: 80, reps: 5, loadType: loadType),
          isNull,
          reason: loadType.name,
        );
      }
    });

    test('refuses missing, zero and negative inputs', () {
      const barbell = LoadType.barbell;

      expect(
        MetricsService.e1rm(weightKg: null, reps: 5, loadType: barbell),
        isNull,
      );
      expect(
        MetricsService.e1rm(weightKg: 100, reps: null, loadType: barbell),
        isNull,
      );
      expect(
        MetricsService.e1rm(weightKg: 0, reps: 5, loadType: barbell),
        isNull,
      );
      expect(
        MetricsService.e1rm(weightKg: -10, reps: 5, loadType: barbell),
        isNull,
      );
      expect(
        MetricsService.e1rm(weightKg: 100, reps: 0, loadType: barbell),
        isNull,
      );
    });

    test('ignores a set that was not completed', () {
      expect(
        MetricsService.setE1rm(
          set(status: SetStatus.skipped, skipReason: SkipReason.pain),
          exercise(),
        ),
        isNull,
      );
    });
  });

  group('tonnage', () {
    test('a barbell set is weight × reps', () {
      expect(MetricsService.setTonnage(set(), exercise()), 500);
    });

    test('a bilateral dumbbell set counts both hands', () {
      // 30 kg per hand × 10 × 2 hands.
      expect(
        MetricsService.setTonnage(
          set(weightKg: 30, reps: 10),
          exercise(loadType: LoadType.dumbbellPerHand),
        ),
        600,
      );
    });

    test('a unilateral set logged as both counts twice', () {
      expect(
        MetricsService.setTonnage(
          set(weightKg: 25, reps: 8),
          exercise(unilateral: true),
        ),
        400,
      );
    });

    test('a unilateral set logged as one side counts once', () {
      expect(
        MetricsService.setTonnage(
          set(weightKg: 25, reps: 8, side: SetSide.left),
          exercise(unilateral: true),
        ),
        200,
      );
    });

    test('unilateral and per-hand multipliers never compound', () {
      // A single-arm dumbbell row is one dumbbell in one hand. Applying both
      // multipliers would report 4× the work actually done.
      expect(
        MetricsService.setTonnage(
          set(weightKg: 25, reps: 8),
          exercise(loadType: LoadType.dumbbellPerHand, unilateral: true),
        ),
        400,
      );
    });

    test('an incomplete or unloadable set contributes nothing', () {
      expect(
        MetricsService.setTonnage(
          set(status: SetStatus.skipped, skipReason: SkipReason.time),
          exercise(),
        ),
        0,
      );
      expect(MetricsService.setTonnage(set(weightKg: null), exercise()), 0);
      expect(MetricsService.setTonnage(set(reps: 0), exercise()), 0);
    });

    test('a session sums its sets and ignores unknown exercises', () {
      final sets = [
        set(index: 0),
        set(index: 1),
        SetLog(
          id: 'set-orphan',
          sessionLogId: 'log-1',
          // Catalog row purged after 90 days.
          exerciseId: 'gone',
          setIndex: 2,
          weightKg: 999,
          reps: 999,
        ),
      ];

      expect(MetricsService.sessionTonnage(sets, {'ex-1': exercise()}), 1000);
    });
  });

  group('adherence', () {
    test('is completed over planned', () {
      expect(
        MetricsService.adherence(completedSets: 17, plannedSets: 20),
        closeTo(0.85, 0.0001),
      );
    });

    test('is null rather than zero when nothing was planned', () {
      // A week with no program is not a week you failed.
      expect(
        MetricsService.adherence(completedSets: 0, plannedSets: 0),
        isNull,
      );
      expect(
        MetricsService.adherence(completedSets: 5, plannedSets: 0),
        isNull,
      );
    });

    test('a skipped set is not a completed one', () {
      final log = SessionLog(
        id: 'log-1',
        scheduledSessionId: 'sched-1',
        startedAt: DateTime(2026, 8, 16, 18),
        endedAt: DateTime(2026, 8, 16, 19, 30),
        sets: [
          set(index: 0),
          set(index: 1, status: SetStatus.skipped, skipReason: SkipReason.pain),
          set(index: 2, status: SetStatus.partial),
        ],
      );

      expect(log.completedSets, 1);
      expect(log.skippedSets, 1);
    });
  });

  group('summary', () {
    final template = SessionTemplate(
      id: 'template-1',
      phaseId: 'phase-1',
      code: 'A',
      title: 'Push',
      orderIndex: 0,
      blocks: const [
        BlockTemplate(
          id: 'block-1',
          sessionTemplateId: 'template-1',
          kind: BlockKind.main,
          title: 'Main',
          orderIndex: 0,
          exercises: [
            ExerciseTemplate(
              id: 'slot-1',
              blockTemplateId: 'block-1',
              exerciseId: 'ex-1',
              orderIndex: 0,
              targetSets: 4,
            ),
          ],
        ),
      ],
    );

    test('rolls a session into one object', () {
      final log = SessionLog(
        id: 'log-1',
        scheduledSessionId: 'sched-1',
        startedAt: DateTime(2026, 8, 16, 18),
        endedAt: DateTime(2026, 8, 16, 19, 30),
        sets: [
          set(index: 0),
          set(index: 1),
          set(index: 2, status: SetStatus.skipped, skipReason: SkipReason.pain),
          set(index: 3, status: SetStatus.skipped, skipReason: SkipReason.time),
        ],
      );

      final summary = MetricsService.summarize(
        log: log,
        template: template,
        exercisesById: {'ex-1': exercise()},
      );

      expect(summary.completedSets, 2);
      expect(summary.plannedSets, 4);
      expect(summary.skippedSets, 2);
      expect(summary.tonnageKg, 1000);
      expect(summary.duration, const Duration(hours: 1, minutes: 30));
      expect(summary.adherence, 0.5);
      // Broken out by reason, so a bad week is legible rather than just
      // smaller.
      expect(summary.skipReasons, {SkipReason.pain: 1, SkipReason.time: 1});
    });

    test('an unplanned session has no adherence to report', () {
      final log = SessionLog(
        id: 'log-1',
        scheduledSessionId: 'sched-1',
        startedAt: DateTime(2026, 8, 16, 18),
        endedAt: DateTime(2026, 8, 16, 18, 40),
        sets: [set()],
      );

      final summary = MetricsService.summarize(
        log: log,
        template: null,
        exercisesById: {'ex-1': exercise()},
      );

      expect(summary.plannedSets, 0);
      expect(summary.adherence, isNull);
    });
  });
}
