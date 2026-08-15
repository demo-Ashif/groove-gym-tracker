/// Data-layer exceptions. Thrown by data sources (Drift DAOs, the Supabase
/// client, the plan parser), caught at the repository boundary and mapped to
/// a domain `Failure`.
///
/// The messages here are **developer-facing only** — they go to logs and
/// crash reports, never to a widget. User-facing copy is resolved from ARB at
/// render time (ADR §12.2 rule 1).
sealed class AppException implements Exception {
  const AppException(this.debugMessage);

  final String debugMessage;

  @override
  String toString() => '$runtimeType: $debugMessage';
}

/// Device is offline or the host is unreachable.
final class NetworkException extends AppException {
  const NetworkException([super.debugMessage = 'No internet connection']);
}

/// The request took too long.
final class RequestTimeoutException extends AppException {
  const RequestTimeoutException([super.debugMessage = 'Request timed out']);
}

/// Non-2xx response from Supabase or an Edge Function.
final class ApiException extends AppException {
  const ApiException({
    required this.statusCode,
    required String debugMessage,
    this.errorCode,
  }) : super(debugMessage);

  final int statusCode;

  /// Postgres/PostgREST error code when one is provided (e.g. `23505`).
  final String? errorCode;
}

/// The anonymous session is invalid and refresh failed.
///
/// Must degrade to offline mode, never to a login wall (ADR §18) — the device
/// is the source of truth and a failed refresh cannot be allowed to block a
/// workout.
final class UnauthorizedException extends AppException {
  const UnauthorizedException([super.debugMessage = 'Session refresh failed']);
}

/// Local database read/write failure. The serious one: SQLite is the source
/// of truth, so this is the class of error that can actually lose a set.
final class CacheException extends AppException {
  const CacheException([super.debugMessage = 'Local storage error']);
}

/// A plan (pasted, dictated or returned by the parser) could not be read.
final class ParseException extends AppException {
  const ParseException([super.debugMessage = 'Could not read the plan']);
}

/// Anything unanticipated.
final class UnexpectedException extends AppException {
  const UnexpectedException([super.debugMessage = 'Unexpected error'])
    : cause = null;

  const UnexpectedException.from(
    this.cause, [
    super.debugMessage = 'Unexpected error',
  ]);

  final Object? cause;
}
