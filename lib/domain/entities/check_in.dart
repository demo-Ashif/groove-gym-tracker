import 'package:equatable/equatable.dart';

import '../values/calendar_date.dart';

/// A body measurement taken on a day (ADR §10).
///
/// One row per date, so re-weighing yourself on the same morning corrects the
/// entry rather than adding a second point to the trend.
///
/// [programId] and [phaseId] are nullable so a check-in outlives the block it
/// was taken during — body-weight history is the one series that must never
/// break at a program boundary.
class CheckIn extends Equatable {
  const CheckIn({
    required this.id,
    required this.date,
    this.programId,
    this.phaseId,
    this.weightKg,
    this.waistCm,
    this.notes,
  });

  final String id;
  final CalendarDate date;

  final String? programId;
  final String? phaseId;

  /// Always kilograms, whatever units the user typed it in.
  final double? weightKg;
  final double? waistCm;

  final String? notes;

  @override
  List<Object?> get props => [
    id,
    date,
    programId,
    phaseId,
    weightKg,
    waistCm,
    notes,
  ];
}
