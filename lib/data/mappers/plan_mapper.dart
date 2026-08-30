import '../../domain/entities/plan.dart';
import '../../domain/values/calendar_date.dart';
import '../db/app_database.dart';
import '../db/daos/plan_dao.dart';
import 'progression_rule_codec.dart';
import 'schedule_pattern_codec.dart';

/// Assembles the flat rows a join returns into the template tree, and maps
/// entities back to the columns a write needs.
abstract final class PlanMapper {
  /// Rows → tree. Children are grouped by parent id in one pass each, so this
  /// stays linear rather than scanning the exercise list once per block.
  static Program toProgram(PlanRows rows) {
    final exercisesByBlock = _groupBy(
      rows.exercises,
      (row) => row.blockTemplateId,
    );
    final blocksBySession = _groupBy(
      rows.blocks,
      (row) => row.sessionTemplateId,
    );
    final sessionsByPhase = _groupBy(rows.sessions, (row) => row.phaseId);

    final phases = rows.phases
        .map(
          (phase) => toPhase(
            phase,
            sessions: (sessionsByPhase[phase.id] ?? const [])
                .map(
                  (session) => toSession(
                    session,
                    blocks: (blocksBySession[session.id] ?? const [])
                        .map(
                          (block) => toBlock(
                            block,
                            exercises: (exercisesByBlock[block.id] ?? const [])
                                .map(toExerciseTemplate)
                                .toList(),
                          ),
                        )
                        .toList(),
                  ),
                )
                .toList(),
          ),
        )
        .toList();

    return toProgramHeader(rows.program).copyWith(phases: phases);
  }

  /// Header only — for the program list, which has no use for the tree.
  static Program toProgramHeader(ProgramRow row) => Program(
    id: row.id,
    name: row.name,
    startDate: CalendarDate.parse(row.startDate),
    endDate: row.endDate == null ? null : CalendarDate.parse(row.endDate!),
    isActive: row.isActive,
    notes: row.notes,
    schedulePattern: SchedulePatternCodec.decode(row.schedulePattern),
  );

  static Phase toPhase(
    PhaseRow row, {
    List<SessionTemplate> sessions = const [],
  }) => Phase(
    id: row.id,
    programId: row.programId,
    name: row.name,
    orderIndex: row.orderIndex,
    startWeek: row.startWeek,
    endWeek: row.endWeek,
    targetSessionMinutes: row.targetSessionMinutes,
    rpeLow: row.rpeLow,
    rpeHigh: row.rpeHigh,
    checkInDueAtEnd: row.checkInDueAtEnd,
    sessions: sessions,
  );

  static SessionTemplate toSession(
    SessionTemplateRow row, {
    List<BlockTemplate> blocks = const [],
  }) => SessionTemplate(
    id: row.id,
    phaseId: row.phaseId,
    code: row.code,
    title: row.title,
    orderIndex: row.orderIndex,
    dayOfWeek: row.dayOfWeek,
    estimatedMinutes: row.estimatedMinutes,
    blocks: blocks,
  );

  static BlockTemplate toBlock(
    BlockTemplateRow row, {
    List<ExerciseTemplate> exercises = const [],
  }) => BlockTemplate(
    id: row.id,
    sessionTemplateId: row.sessionTemplateId,
    kind: row.kind,
    title: row.title,
    orderIndex: row.orderIndex,
    targetMinutes: row.targetMinutes,
    notes: row.notes,
    exercises: exercises,
  );

  static ExerciseTemplate toExerciseTemplate(ExerciseTemplateRow row) =>
      ExerciseTemplate(
        id: row.id,
        blockTemplateId: row.blockTemplateId,
        exerciseId: row.exerciseId,
        orderIndex: row.orderIndex,
        targetSets: row.targetSets,
        targetReps: row.targetReps,
        targetDurationSec: row.targetDurationSec,
        targetLoadKg: row.targetLoadKg,
        targetLoadText: row.targetLoadText,
        targetRpe: row.targetRpe,
        restSeconds: row.restSeconds,
        perSide: row.perSide,
        tempo: row.tempo,
        progression: ProgressionRuleCodec.decode(row.progressionRule),
        notes: row.notes,
      );

  static Map<K, List<V>> _groupBy<K, V>(List<V> items, K Function(V) key) {
    final grouped = <K, List<V>>{};
    for (final item in items) {
      grouped.putIfAbsent(key(item), () => []).add(item);
    }
    return grouped;
  }
}

/// Only the tree assembly needs to replace phases wholesale, so `copyWith`
/// lives here rather than widening the entity's surface for one caller.
extension on Program {
  Program copyWith({List<Phase>? phases}) => Program(
    id: id,
    name: name,
    startDate: startDate,
    endDate: endDate,
    isActive: isActive,
    notes: notes,
    schedulePattern: schedulePattern,
    phases: phases ?? this.phases,
  );
}
