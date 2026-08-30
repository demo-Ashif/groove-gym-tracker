import 'package:equatable/equatable.dart';

import '../enums/training_enums.dart';
import '../values/calendar_date.dart';
import '../values/progression_rule.dart';
import '../values/schedule_pattern.dart';

/// The template tree: `Program → Phase → SessionTemplate → BlockTemplate →
/// ExerciseTemplate` (ADR §4.1).
///
/// This is the **prescription**, never the log. Editing anything here applies
/// forward only; completed sessions are immutable (ADR §8.2). History must not
/// lie.
///
/// Children are carried inline because that is how the builder reads them —
/// one query for a whole program, one object to render. Writes go through the
/// repository field by field, so nothing here has to be a mutable tree.
class Program extends Equatable {
  const Program({
    required this.id,
    required this.name,
    required this.startDate,
    this.endDate,
    this.isActive = false,
    this.notes,
    this.schedulePattern,
    this.phases = const [],
  });

  final String id;
  final String name;
  final CalendarDate startDate;

  /// Null while the program is open-ended. Set when the last phase's end week
  /// is known.
  final CalendarDate? endDate;

  /// Exactly one program is active at a time — it is the one Today reads.
  final bool isActive;

  final String? notes;

  /// How the program repeats. Null until the schedule is first committed —
  /// which is also what tells the editor whether it is drawing a fresh week
  /// strip or an existing one.
  final SchedulePattern? schedulePattern;

  /// Ordered by [Phase.orderIndex]. Empty when only the program header has
  /// been loaded.
  final List<Phase> phases;

  /// Total planned length. Falls back to the phase weeks when no end date has
  /// been set, which is the usual state during a build.
  int get weekCount {
    if (endDate case final end?) {
      return (startDate.daysUntil(end) / 7).ceil();
    }
    if (phases.isEmpty) return 0;
    return phases.map((phase) => phase.endWeek).reduce((a, b) => a > b ? a : b);
  }

  /// The 1-based program week [date] falls in, or null before the program
  /// starts. Week 1 is the seven days from [startDate] inclusive.
  int? weekOf(CalendarDate date) {
    final elapsed = startDate.daysUntil(date);
    if (elapsed < 0) return null;
    return elapsed ~/ 7 + 1;
  }

  /// The phase covering a 1-based program week, or null past the end.
  Phase? phaseForWeek(int week) {
    for (final phase in phases) {
      if (week >= phase.startWeek && week <= phase.endWeek) return phase;
    }
    return null;
  }

  int get sessionTemplateCount =>
      phases.fold(0, (sum, phase) => sum + phase.sessions.length);

  @override
  List<Object?> get props => [
    id,
    name,
    startDate,
    endDate,
    isActive,
    notes,
    schedulePattern,
    phases,
  ];
}

/// A training block within a program — "Cycle 1 — Foundation".
class Phase extends Equatable {
  const Phase({
    required this.id,
    required this.programId,
    required this.name,
    required this.orderIndex,
    required this.startWeek,
    required this.endWeek,
    this.targetSessionMinutes,
    this.rpeLow,
    this.rpeHigh,
    this.checkInDueAtEnd = true,
    this.sessions = const [],
  });

  final String id;
  final String programId;
  final String name;
  final int orderIndex;

  /// Inclusive, 1-based program weeks.
  final int startWeek;
  final int endWeek;

  final int? targetSessionMinutes;

  /// The RPE band the phase is meant to be run at.
  final double? rpeLow;
  final double? rpeHigh;

  /// Whether finishing this phase raises a check-in prompt (ADR §10.1).
  final bool checkInDueAtEnd;

  final List<SessionTemplate> sessions;

  int get weekCount => endWeek - startWeek + 1;

  bool coversWeek(int week) => week >= startWeek && week <= endWeek;

  @override
  List<Object?> get props => [
    id,
    programId,
    name,
    orderIndex,
    startWeek,
    endWeek,
    targetSessionMinutes,
    rpeLow,
    rpeHigh,
    checkInDueAtEnd,
    sessions,
  ];
}

/// One day's prescription — "Day A · Push + Core".
class SessionTemplate extends Equatable {
  const SessionTemplate({
    required this.id,
    required this.phaseId,
    required this.code,
    required this.title,
    required this.orderIndex,
    this.dayOfWeek,
    this.estimatedMinutes,
    this.blocks = const [],
  });

  final String id;
  final String phaseId;

  /// The letter the plan uses — "A", "B". User-authored, never translated.
  final String code;

  final String title;
  final int orderIndex;

  /// ISO-8601 weekday, 1 = Monday … 7 = Sunday. Null when the session isn't
  /// pinned to a weekday. Never use this to decide which day a week *starts*
  /// on — that is locale data (ADR §12.2 rule 8).
  final int? dayOfWeek;

  final int? estimatedMinutes;

  final List<BlockTemplate> blocks;

  /// What the session actually asks of you, as opposed to what was estimated.
  int get totalSets => blocks.fold(0, (sum, block) => sum + block.totalSets);

  int get exerciseCount =>
      blocks.fold(0, (sum, block) => sum + block.exercises.length);

  @override
  List<Object?> get props => [
    id,
    phaseId,
    code,
    title,
    orderIndex,
    dayOfWeek,
    estimatedMinutes,
    blocks,
  ];
}

/// A section of a session — warm-up, main work, conditioning.
class BlockTemplate extends Equatable {
  const BlockTemplate({
    required this.id,
    required this.sessionTemplateId,
    required this.kind,
    required this.title,
    required this.orderIndex,
    this.targetMinutes,
    this.notes,
    this.exercises = const [],
  });

  final String id;
  final String sessionTemplateId;
  final BlockKind kind;
  final String title;
  final int orderIndex;
  final int? targetMinutes;
  final String? notes;

  final List<ExerciseTemplate> exercises;

  int get totalSets =>
      exercises.fold(0, (sum, exercise) => sum + exercise.targetSets);

  @override
  List<Object?> get props => [
    id,
    sessionTemplateId,
    kind,
    title,
    orderIndex,
    targetMinutes,
    notes,
    exercises,
  ];
}

/// The prescription itself: one exercise slot in a block.
class ExerciseTemplate extends Equatable {
  const ExerciseTemplate({
    required this.id,
    required this.blockTemplateId,
    required this.exerciseId,
    required this.orderIndex,
    required this.targetSets,
    this.targetReps,
    this.targetDurationSec,
    this.targetLoadKg,
    this.targetLoadText,
    this.targetRpe,
    this.restSeconds = 90,
    this.perSide = false,
    this.tempo,
    this.progression = const ProgressionRule.fixed(),
    this.notes,
  });

  final String id;
  final String blockTemplateId;

  /// Points at the catalog, which is what makes "RDL over 10 weeks" survive
  /// across programs (ADR §4.3).
  final String exerciseId;

  final int orderIndex;
  final int targetSets;

  /// A single prescribed rep count. Null for time-based work, where
  /// [targetDurationSec] carries the prescription instead — the two are
  /// mutually exclusive, enforced by the repository.
  final int? targetReps;

  /// Prescribed working time in seconds, for exercises measured by the clock
  /// rather than by reps: stationary bike, treadmill, cross trainer, plank.
  /// Null for rep-based work.
  final int? targetDurationSec;

  /// Planned working load. Optional — a prescription may legitimately say
  /// "3 × 10" with the weight left to the day — but recording it is what lets
  /// Insights chart planned workload against actual.
  final double? targetLoadKg;

  /// For prescriptions that aren't a number — "bodyweight", "light band".
  /// Literal text in the plan's own language.
  final String? targetLoadText;

  final double? targetRpe;
  final int restSeconds;

  /// Reps are per side rather than total.
  final bool perSide;

  /// Tempo notation, e.g. `3-1-1-0`. Symbols only.
  final String? tempo;

  final ProgressionRule progression;
  final String? notes;

  /// Measured by the clock rather than by reps. Drives which stepper the slot
  /// form shows and which field the logger writes.
  bool get isTimeBased => targetDurationSec != null;

  /// Total prescribed reps, counting both sides for unilateral work. This is
  /// the denominator adherence is measured against (ADR §4.4). Null for
  /// time-based work, which has no rep denominator to measure against.
  int? get plannedReps {
    final reps = targetReps;
    if (reps == null) return null;
    return reps * targetSets * (perSide ? 2 : 1);
  }

  /// Total prescribed working time across every set, for the same role
  /// [plannedReps] plays for rep-based work.
  int? get plannedDurationSec {
    final duration = targetDurationSec;
    if (duration == null) return null;
    return duration * targetSets;
  }

  @override
  List<Object?> get props => [
    id,
    blockTemplateId,
    exerciseId,
    orderIndex,
    targetSets,
    targetReps,
    targetDurationSec,
    targetLoadKg,
    targetLoadText,
    targetRpe,
    restSeconds,
    perSide,
    tempo,
    progression,
    notes,
  ];
}
