import '../../domain/entities/session_log.dart';
import '../db/app_database.dart';
import '../db/daos/log_dao.dart';

/// Rows → entities for the logging loop.
extension SessionLogRowsMapper on SessionLogRows {
  SessionLog toEntity() => SessionLog(
    id: log.id,
    scheduledSessionId: log.scheduledSessionId,
    startedAt: log.startedAt,
    endedAt: log.endedAt,
    sessionRpe: log.sessionRpe,
    energy: log.energy,
    notes: log.notes,
    bodyweightAtTimeKg: log.bodyweightAtTimeKg,
    sets: sets.map((row) => row.toEntity()).toList(growable: false),
  );
}

extension SetLogRowMapper on SetLogRow {
  SetLog toEntity() => SetLog(
    id: id,
    sessionLogId: sessionLogId,
    exerciseTemplateId: exerciseTemplateId,
    exerciseId: exerciseId,
    setIndex: setIndex,
    side: side,
    status: status,
    reps: reps,
    weightKg: weightKg,
    durationSec: durationSec,
    distanceM: distanceM,
    rpe: rpe,
    isPr: isPr,
    skipReason: skipReason,
    substitutedForExerciseId: substitutedForExerciseId,
    note: note,
  );
}
