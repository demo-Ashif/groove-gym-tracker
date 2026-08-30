import '../logging/app_logger.dart';
import 'failure.dart';

/// Lightweight result type. Repositories return `Result<T>` so the
/// presentation layer handles success and failure exhaustively:
///
/// ```dart
/// switch (await repository.load()) {
///   case Success(:final data): ...
///   case Err(:final failure): ...
/// }
/// ```
sealed class Result<T> {
  const Result();

  /// Runs [body], mapping any thrown exception to a domain [Failure]. The
  /// standard repository boundary:
  ///
  /// ```dart
  /// Future<Result<Program>> active() =>
  ///     Result.guard(() async => (await _dao.activeProgram()).toEntity());
  /// ```
  static Future<Result<T>> guard<T>(Future<T> Function() body) async {
    try {
      return Success(await body());
    } catch (error, stackTrace) {
      AppLogger.e('Result.guard caught', error: error, stackTrace: stackTrace);
      return Err(Failure.fromException(error));
    }
  }

  bool get isSuccess => this is Success<T>;

  T? get dataOrNull => switch (this) {
    Success(:final data) => data,
    Err() => null,
  };

  Failure? get failureOrNull => switch (this) {
    Success() => null,
    Err(:final failure) => failure,
  };

  R fold<R>(
    R Function(T data) onSuccess,
    R Function(Failure failure) onFailure,
  ) => switch (this) {
    Success(:final data) => onSuccess(data),
    Err(:final failure) => onFailure(failure),
  };

  Result<R> map<R>(R Function(T data) transform) => switch (this) {
    Success(:final data) => Success(transform(data)),
    Err(:final failure) => Err(failure),
  };
}

final class Success<T> extends Result<T> {
  const Success(this.data);

  final T data;
}

final class Err<T> extends Result<T> {
  const Err(this.failure);

  final Failure failure;
}
