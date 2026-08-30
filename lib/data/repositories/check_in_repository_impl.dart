import '../../core/error/app_exception.dart';
import '../../core/error/result.dart';
import '../../domain/entities/check_in.dart';
import '../../domain/repositories/check_in_repository.dart';
import '../../domain/values/calendar_date.dart';
import '../db/app_database.dart';
import '../db/daos/check_in_dao.dart';

/// Drift-backed body measurements.
class CheckInRepositoryImpl implements CheckInRepository {
  const CheckInRepositoryImpl(this._dao);

  final CheckInDao _dao;

  @override
  Stream<List<CheckIn>> watchCheckIns({int limit = 200}) => _dao
      .watchCheckIns(limit: limit)
      .map((rows) => rows.map(_toEntity).toList(growable: false));

  @override
  Stream<CheckIn?> watchLatestWeight() => _dao.watchLatestWeight().map(
    (row) => row == null ? null : _toEntity(row),
  );

  @override
  Future<Result<CheckIn>> record({
    required CalendarDate date,
    double? weightKg,
    double? waistCm,
    String? programId,
    String? phaseId,
    String? notes,
  }) {
    return Result.guard(() async {
      // A bodyweight outside this is a typo or the wrong unit, and it would
      // poison every BMI and relative-strength number computed from it.
      if (weightKg != null && (weightKg <= 0 || weightKg > 500)) {
        throw const ParseException('That weight is not a plausible bodyweight');
      }
      if (waistCm != null && (waistCm <= 0 || waistCm > 300)) {
        throw const ParseException('That waist measurement is out of range');
      }

      final row = await _dao.upsert(
        date: date.toIso(),
        weightKg: weightKg,
        waistCm: waistCm,
        programId: programId,
        phaseId: phaseId,
        notes: notes,
      );
      return _toEntity(row);
    });
  }

  @override
  Future<Result<void>> delete(String id) =>
      Result.guard(() => _dao.softDelete(id));

  CheckIn _toEntity(CheckInRow row) => CheckIn(
    id: row.id,
    date: CalendarDate.parse(row.date),
    programId: row.programId,
    phaseId: row.phaseId,
    weightKg: row.weightKg,
    waistCm: row.waistCm,
    notes: row.notes,
  );
}
