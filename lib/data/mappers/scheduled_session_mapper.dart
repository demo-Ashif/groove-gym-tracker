import '../../domain/entities/scheduled_session.dart';
import '../../domain/values/calendar_date.dart';
import '../db/app_database.dart';

/// Row → entity for the materialized calendar.
extension ScheduledSessionRowMapper on ScheduledSessionRow {
  ScheduledSession toEntity() => ScheduledSession(
    id: id,
    programId: programId,
    // The column is constrained to `YYYY-MM-DD`, so a parse failure here means
    // the row is corrupt and should surface rather than be guessed at.
    date: CalendarDate.parse(date),
    weekNumber: weekNumber,
    kind: kind,
    sessionTemplateId: sessionTemplateId,
    status: status,
    plannedDurationMin: plannedDurationMin,
    overrideReason: overrideReason,
  );
}
