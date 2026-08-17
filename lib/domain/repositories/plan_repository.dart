import '../../core/error/result.dart';
import '../entities/plan.dart';
import '../enums/training_enums.dart';
import '../values/calendar_date.dart';
import '../values/progression_rule.dart';

/// The template tree, as the builder and the scheduler see it.
///
/// **Updates take a whole entity, not a patch.** A partial update with
/// optional arguments cannot express "clear this field" — null is
/// indistinguishable from "leave it alone" — and the builder is holding the
/// entity anyway.
///
/// **Deletes are soft, and cascade by hand.** SQLite's `ON DELETE CASCADE`
/// only fires for real deletes, so hiding a phase has to hide its sessions,
/// blocks and exercise slots in the same transaction. Half a hidden subtree is
/// a session that renders with no blocks.
abstract interface class PlanRepository {
  /// Program headers, without their phases. For a list screen — loading four
  /// full trees to render four rows is waste.
  Stream<List<Program>> watchPrograms();

  /// The active program with its whole tree, or null when none is active.
  /// This is what Today and the scheduler read.
  Stream<Program?> watchActiveProgram();

  /// One program with its whole tree, live. Null once the program is deleted,
  /// which is the editor's cue to leave the screen rather than sit on stale
  /// rows.
  Stream<Program?> watchProgram(String id);

  /// One program with its whole tree. Null when the id is unknown.
  Future<Result<Program?>> loadProgram(String id);

  Future<Result<Program>> createProgram({
    required String name,
    required CalendarDate startDate,
    String? notes,
  });

  Future<Result<void>> updateProgram(Program program);

  /// Exactly one program is active at a time; this clears the others in the
  /// same transaction.
  Future<Result<void>> setActiveProgram(String id);

  Future<Result<void>> deleteProgram(String id);

  Future<Result<Phase>> addPhase({
    required String programId,
    required String name,
    required int startWeek,
    required int endWeek,
  });

  Future<Result<void>> updatePhase(Phase phase);

  Future<Result<void>> deletePhase(String id);

  Future<Result<SessionTemplate>> addSession({
    required String phaseId,
    required String code,
    required String title,
    int? dayOfWeek,
  });

  Future<Result<void>> updateSession(SessionTemplate session);

  Future<Result<void>> deleteSession(String id);

  Future<Result<BlockTemplate>> addBlock({
    required String sessionTemplateId,
    required BlockKind kind,
    required String title,
  });

  Future<Result<void>> updateBlock(BlockTemplate block);

  Future<Result<void>> deleteBlock(String id);

  Future<Result<ExerciseTemplate>> addExercise({
    required String blockTemplateId,
    required String exerciseId,
    required int targetSets,
    int? targetReps,
    int? targetDurationSec,
    double? targetLoadKg,
    int restSeconds,
    bool perSide,
    ProgressionRule progression,
  });

  Future<Result<void>> updateExercise(ExerciseTemplate exercise);

  Future<Result<void>> deleteExercise(String id);

  /// Rewrites `order_index` to match the given order. Takes the full list of
  /// sibling ids rather than a from/to pair, so a drag that raced another edit
  /// can't leave two rows claiming the same position.
  Future<Result<void>> reorderPhases(List<String> orderedIds);

  Future<Result<void>> reorderSessions(List<String> orderedIds);

  Future<Result<void>> reorderBlocks(List<String> orderedIds);

  Future<Result<void>> reorderExercises(List<String> orderedIds);
}
