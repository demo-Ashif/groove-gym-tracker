import 'package:equatable/equatable.dart';

import 'app_exception.dart';

/// Domain-layer failures. What repositories hand the presentation layer
/// inside a `Result` — presentation never sees a raw exception.
///
/// **A failure carries a kind, not a sentence.** The user-facing wording is
/// resolved from ARB at render time (`ErrorView`), because a message baked in
/// here would be an untranslatable English string sitting in the domain layer
/// (ADR §12.2 rule 1). [debugMessage] is for logs and crash reports only.
sealed class Failure extends Equatable {
  const Failure({this.debugMessage});

  /// Maps any thrown object to a domain failure. Repositories use this at
  /// their boundary — see `Result.guard`.
  factory Failure.fromException(Object error) => switch (error) {
    NetworkException(:final debugMessage) => NetworkFailure(
      debugMessage: debugMessage,
    ),
    RequestTimeoutException(:final debugMessage) => NetworkFailure(
      debugMessage: debugMessage,
    ),
    UnauthorizedException(:final debugMessage) => AuthFailure(
      debugMessage: debugMessage,
    ),
    ApiException(:final debugMessage, :final statusCode, :final errorCode) =>
      ServerFailure(
        statusCode: statusCode,
        errorCode: errorCode,
        debugMessage: debugMessage,
      ),
    CacheException(:final debugMessage) => StorageFailure(
      debugMessage: debugMessage,
    ),
    ParseException(:final debugMessage) => ParseFailure(
      debugMessage: debugMessage,
    ),
    AppException(:final debugMessage) => UnexpectedFailure(
      debugMessage: debugMessage,
    ),
    _ => UnexpectedFailure(debugMessage: error.toString()),
  };

  /// Developer-facing detail. Never rendered.
  final String? debugMessage;

  @override
  List<Object?> get props => [debugMessage];
}

/// Offline or unreachable host. Expected, and almost never worth interrupting
/// the user for — the app is designed to work without a network.
final class NetworkFailure extends Failure {
  const NetworkFailure({super.debugMessage});
}

final class ServerFailure extends Failure {
  const ServerFailure({this.statusCode, this.errorCode, super.debugMessage});

  final int? statusCode;
  final String? errorCode;

  @override
  List<Object?> get props => [statusCode, errorCode, debugMessage];
}

/// Anonymous session invalid and refresh failed. Degrade to offline; never
/// show a login wall.
final class AuthFailure extends Failure {
  const AuthFailure({super.debugMessage});
}

/// Bad input, caught before it reaches storage. [field] lets a form point at
/// the offending control; the message itself comes from ARB.
final class ValidationFailure extends Failure {
  const ValidationFailure({this.field, super.debugMessage});

  final String? field;

  @override
  List<Object?> get props => [field, debugMessage];
}

/// Local database failure — the one that can actually lose data.
final class StorageFailure extends Failure {
  const StorageFailure({super.debugMessage});
}

/// A plan could not be read well enough to import.
final class ParseFailure extends Failure {
  const ParseFailure({super.debugMessage});
}

final class UnexpectedFailure extends Failure {
  const UnexpectedFailure({super.debugMessage});
}
