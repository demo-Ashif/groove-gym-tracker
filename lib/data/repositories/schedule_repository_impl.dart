import '../../core/error/app_exception.dart';
import '../../core/error/result.dart';
import '../../domain/entities/scheduled_session.dart';
import '../../domain/enums/training_enums.dart';
import '../../domain/repositories/plan_repository.dart';
import '../../domain/repositories/schedule_repository.dart';
import '../../domain/services/schedule_materializer.dart';
import '../../domain/values/calendar_date.dart';
import '../../domain/values/schedule_pattern.dart';
import '../db/app_database.dart';
import '../db/daos/schedule_dao.dart';
import '../mappers/schedule_pattern_codec.dart';
import '../mappers/scheduled_session_mapper.dart';

/// Drift-backed calendar.
///
/// Materialization is deliberately a **repository** concern rather than a DAO
/// one: expanding a pattern needs the program tree, and the rule about what a
/// re-commit may touch is domain logic that must stay testable without SQLite
/// ([ScheduleMaterializer]). The DAO only applies the diff it is handed.
class ScheduleRepositoryImpl implements ScheduleRepository {
  const ScheduleRepositoryImpl({
    required ScheduleDao dao,
    required PlanRepository planRepository,
    DateTime Function()? now,
  }) : _dao = dao,
       _plan = planRepository,
       _now = now ?? DateTime.now;

  final ScheduleDao _dao;
  final PlanRepository _plan;

  /// Injectable so "today" is an input rather than a hidden dependency on the
  /// device clock.
  final DateTime Function() _now;

  @override
  Stream<List<ScheduledSession>> watchProgramSchedule(String programId) =>
      _dao.watchProgramSchedule(programId).map(_toEntities);

  @override
  Future<Result<ScheduledSession?>> findById(String id) =>
      Result.guard(() async => (await _dao.findById(id))?.toEntity());

  @override
  Stream<List<ScheduledSession>> watchRange({
    required CalendarDate from,
    required CalendarDate to,
  }) => _dao
      .watchRange(fromDate: from.toIso(), toDate: to.toIso())
      .map(_toEntities);

  @override
  Future<Result<({int added, int removed})>> commitSchedule({
    required String programId,
    required SchedulePattern pattern,
  }) => Result.guard(() async {
    final program = (await _plan.loadProgram(programId)).dataOrNull;
    if (program == null) {
      throw const CacheException('Program not found');
    }
    if (program.phases.isEmpty) {
      // Nothing to expand against: a schedule with no phases would be a run of
      // rest days pretending to be a program.
      throw const ParseException('Program has no phases to schedule');
    }

    final desired = ScheduleMaterializer.plan(
      program: program,
      pattern: pattern,
    );

    final existing = _toEntities(await _dao.loadProgramSchedule(programId));

    final diff = ScheduleMaterializer.diff(
      existing: existing,
      desired: desired,
      today: CalendarDate.from(_now()),
    );

    await _dao.commitSchedule(
      programId: programId,
      diff: diff,
      encodedPattern: SchedulePatternCodec.encode(pattern),
    );

    return (added: diff.toInsert.length, removed: diff.toRemove.length);
  });

  @override
  Future<Result<void>> setStatus({
    required String id,
    required ScheduledSessionStatus status,
  }) => Result.guard(() => _dao.setStatus(id, status));

  @override
  Future<Result<void>> convertKind({
    required String id,
    required ScheduledSessionKind kind,
    String? reason,
  }) =>
      Result.guard(() => _dao.convertKind(id: id, kind: kind, reason: reason));

  @override
  Future<Result<void>> reschedule({
    required String id,
    required CalendarDate date,
  }) => Result.guard(() => _dao.reschedule(id: id, date: date.toIso()));

  List<ScheduledSession> _toEntities(List<ScheduledSessionRow> rows) =>
      rows.map((row) => row.toEntity()).toList(growable: false);
}
