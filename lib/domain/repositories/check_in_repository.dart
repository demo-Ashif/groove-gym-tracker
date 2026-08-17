import '../../core/error/result.dart';
import '../entities/check_in.dart';
import '../values/calendar_date.dart';

/// Body measurements over time (ADR §10).
abstract interface class CheckInRepository {
  /// Every check-in, newest first — the weight trend.
  Stream<List<CheckIn>> watchCheckIns({int limit});

  /// The most recent check-in carrying a weight, which is what BMI and
  /// relative-strength maths read. Null before the first one.
  Stream<CheckIn?> watchLatestWeight();

  /// Records a measurement for [date], replacing any already on that date.
  ///
  /// Upsert rather than insert: stepping on the scale twice in one morning is
  /// a correction, not two data points.
  Future<Result<CheckIn>> record({
    required CalendarDate date,
    double? weightKg,
    double? waistCm,
    String? programId,
    String? phaseId,
    String? notes,
  });

  Future<Result<void>> delete(String id);
}
