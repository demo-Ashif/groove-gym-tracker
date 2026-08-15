import 'package:drift/drift.dart';

import '../../core/error/app_exception.dart';
import '../../core/error/result.dart';
import '../../domain/entities/plan.dart';
import '../../domain/enums/training_enums.dart';
import '../../domain/repositories/plan_repository.dart';
import '../../domain/values/calendar_date.dart';
import '../../domain/values/progression_rule.dart';
import '../db/app_database.dart';
import '../db/daos/plan_dao.dart';
import '../mappers/plan_mapper.dart';
import '../mappers/progression_rule_codec.dart';

/// Drift-backed template tree.
///
/// Validation that protects the *model* lives here rather than in the UI: a
/// phase with `endWeek < startWeek` or a session with no code would be
/// accepted by SQLite and only surface later as a program that can't be
/// scheduled.
class PlanRepositoryImpl implements PlanRepository {
  const PlanRepositoryImpl(this._dao);

  final PlanDao _dao;

  @override
  Stream<List<Program>> watchPrograms() => _dao.watchPrograms().map(
    (rows) => rows.map(PlanMapper.toProgramHeader).toList(growable: false),
  );

  @override
  Stream<Program?> watchActiveProgram() => _dao.watchActivePlan().map(
    (rows) => rows == null ? null : PlanMapper.toProgram(rows),
  );

  @override
  Stream<Program?> watchProgram(String id) => _dao
      .watchPlan(id)
      .map((rows) => rows == null ? null : PlanMapper.toProgram(rows));

  @override
  Future<Result<Program?>> loadProgram(String id) => Result.guard(() async {
    final rows = await _dao.loadPlan(id);
    return rows == null ? null : PlanMapper.toProgram(rows);
  });

  @override
  Future<Result<Program>> createProgram({
    required String name,
    required CalendarDate startDate,
    String? notes,
  }) => Result.guard(() async {
    final trimmed = _require(name, 'Program name');

    final row = await _dao.createProgram(
      name: trimmed,
      startDate: startDate.toIso(),
      notes: notes,
    );
    return PlanMapper.toProgramHeader(row);
  });

  @override
  Future<Result<void>> updateProgram(Program program) => Result.guard(() async {
    final name = _require(program.name, 'Program name');

    if (program.endDate case final end?) {
      if (end.isBefore(program.startDate)) {
        throw const ParseException('Program ends before it starts');
      }
    }

    await _dao.updateProgram(
      id: program.id,
      name: name,
      startDate: program.startDate.toIso(),
      endDate: program.endDate?.toIso(),
      notes: program.notes,
    );
  });

  @override
  Future<Result<void>> setActiveProgram(String id) =>
      Result.guard(() => _dao.setActiveProgram(id));

  @override
  Future<Result<void>> deleteProgram(String id) =>
      Result.guard(() => _dao.deleteProgram(id));

  @override
  Future<Result<Phase>> addPhase({
    required String programId,
    required String name,
    required int startWeek,
    required int endWeek,
  }) => Result.guard(() async {
    final trimmed = _require(name, 'Phase name');
    _requireWeekRange(startWeek, endWeek);

    final row = await _dao.createPhase(
      programId: programId,
      name: trimmed,
      startWeek: startWeek,
      endWeek: endWeek,
    );
    return PlanMapper.toPhase(row);
  });

  @override
  Future<Result<void>> updatePhase(Phase phase) => Result.guard(() async {
    final name = _require(phase.name, 'Phase name');
    _requireWeekRange(phase.startWeek, phase.endWeek);

    if (phase.rpeLow case final low?) {
      if (phase.rpeHigh case final high?) {
        if (low > high) {
          throw const ParseException('RPE band is inverted');
        }
      }
    }

    await _dao.updatePhase(
      PhasesCompanion(
        name: Value(name),
        startWeek: Value(phase.startWeek),
        endWeek: Value(phase.endWeek),
        targetSessionMinutes: Value(phase.targetSessionMinutes),
        rpeLow: Value(phase.rpeLow),
        rpeHigh: Value(phase.rpeHigh),
        checkInDueAtEnd: Value(phase.checkInDueAtEnd),
      ),
      phase.id,
    );
  });

  @override
  Future<Result<void>> deletePhase(String id) =>
      Result.guard(() => _dao.deletePhase(id));

  @override
  Future<Result<SessionTemplate>> addSession({
    required String phaseId,
    required String code,
    required String title,
    int? dayOfWeek,
  }) => Result.guard(() async {
    final row = await _dao.createSession(
      phaseId: phaseId,
      code: _require(code, 'Session code'),
      title: _require(title, 'Session title'),
      dayOfWeek: _checkedWeekday(dayOfWeek),
    );
    return PlanMapper.toSession(row);
  });

  @override
  Future<Result<void>> updateSession(SessionTemplate session) =>
      Result.guard(() async {
        await _dao.updateSession(
          SessionTemplatesCompanion(
            code: Value(_require(session.code, 'Session code')),
            title: Value(_require(session.title, 'Session title')),
            dayOfWeek: Value(_checkedWeekday(session.dayOfWeek)),
            estimatedMinutes: Value(session.estimatedMinutes),
          ),
          session.id,
        );
      });

  @override
  Future<Result<void>> deleteSession(String id) =>
      Result.guard(() => _dao.deleteSession(id));

  @override
  Future<Result<BlockTemplate>> addBlock({
    required String sessionTemplateId,
    required BlockKind kind,
    required String title,
  }) => Result.guard(() async {
    final row = await _dao.createBlock(
      sessionTemplateId: sessionTemplateId,
      kind: kind,
      title: _require(title, 'Block title'),
    );
    return PlanMapper.toBlock(row);
  });

  @override
  Future<Result<void>> updateBlock(BlockTemplate block) =>
      Result.guard(() async {
        await _dao.updateBlock(
          BlockTemplatesCompanion(
            kind: Value(block.kind),
            title: Value(_require(block.title, 'Block title')),
            targetMinutes: Value(block.targetMinutes),
            notes: Value(block.notes),
          ),
          block.id,
        );
      });

  @override
  Future<Result<void>> deleteBlock(String id) =>
      Result.guard(() => _dao.deleteBlock(id));

  @override
  Future<Result<ExerciseTemplate>> addExercise({
    required String blockTemplateId,
    required String exerciseId,
    required int targetSets,
    int? targetRepsMin,
    int? targetRepsMax,
    int restSeconds = 90,
    bool perSide = false,
    ProgressionRule progression = const ProgressionRule.fixed(),
  }) => Result.guard(() async {
    _requireSets(targetSets);
    _requireRepRange(targetRepsMin, targetRepsMax);

    final row = await _dao.createExercise(
      ExerciseTemplatesCompanion.insert(
        blockTemplateId: blockTemplateId,
        exerciseId: exerciseId,
        // Overwritten by the DAO, which appends to the end of the block.
        orderIndex: 0,
        targetSets: targetSets,
        targetRepsMin: Value(targetRepsMin),
        targetRepsMax: Value(targetRepsMax),
        restSeconds: Value(restSeconds),
        perSide: Value(perSide),
        progressionRule: Value(ProgressionRuleCodec.encode(progression)),
      ),
    );
    return PlanMapper.toExerciseTemplate(row);
  });

  @override
  Future<Result<void>> updateExercise(ExerciseTemplate exercise) =>
      Result.guard(() async {
        _requireSets(exercise.targetSets);
        _requireRepRange(exercise.targetRepsMin, exercise.targetRepsMax);

        await _dao.updateExercise(
          ExerciseTemplatesCompanion(
            exerciseId: Value(exercise.exerciseId),
            targetSets: Value(exercise.targetSets),
            targetRepsMin: Value(exercise.targetRepsMin),
            targetRepsMax: Value(exercise.targetRepsMax),
            targetLoadKg: Value(exercise.targetLoadKg),
            targetLoadText: Value(exercise.targetLoadText),
            targetRpe: Value(exercise.targetRpe),
            restSeconds: Value(exercise.restSeconds),
            perSide: Value(exercise.perSide),
            tempo: Value(exercise.tempo),
            progressionRule: Value(
              ProgressionRuleCodec.encode(exercise.progression),
            ),
            notes: Value(exercise.notes),
          ),
          exercise.id,
        );
      });

  @override
  Future<Result<void>> deleteExercise(String id) =>
      Result.guard(() => _dao.deleteExercise(id));

  @override
  Future<Result<void>> reorderPhases(List<String> orderedIds) =>
      Result.guard(() => _dao.reorderPhases(orderedIds));

  @override
  Future<Result<void>> reorderSessions(List<String> orderedIds) =>
      Result.guard(() => _dao.reorderSessions(orderedIds));

  @override
  Future<Result<void>> reorderBlocks(List<String> orderedIds) =>
      Result.guard(() => _dao.reorderBlocks(orderedIds));

  @override
  Future<Result<void>> reorderExercises(List<String> orderedIds) =>
      Result.guard(() => _dao.reorderExercises(orderedIds));

  // --- validation ----------------------------------------------------------

  static String _require(String value, String field) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw ParseException('$field cannot be empty');
    }
    return trimmed;
  }

  static void _requireWeekRange(int startWeek, int endWeek) {
    if (startWeek < 1) {
      throw const ParseException('Program weeks are 1-based');
    }
    if (endWeek < startWeek) {
      throw const ParseException('Phase ends before it starts');
    }
  }

  static void _requireSets(int targetSets) {
    if (targetSets < 1) {
      throw const ParseException('An exercise needs at least one set');
    }
  }

  static void _requireRepRange(int? min, int? max) {
    if (min != null && min < 1) {
      throw const ParseException('Rep targets start at 1');
    }
    if (min != null && max != null && max < min) {
      throw const ParseException('Rep range is inverted');
    }
  }

  /// ISO-8601 weekday or nothing. A 0 or an 8 here would silently never match
  /// a real day when the schedule is materialized.
  static int? _checkedWeekday(int? dayOfWeek) {
    if (dayOfWeek == null) return null;
    if (dayOfWeek < DateTime.monday || dayOfWeek > DateTime.sunday) {
      throw const ParseException('Weekday must be 1 (Mon) to 7 (Sun)');
    }
    return dayOfWeek;
  }
}
