import 'package:core/src/errors/app_error.dart';

/// A Result wrapper for API calls.
///
/// Encapsulates either a successful value [T] or an [AppError].
sealed class Result<T> {
  const Result();

  /// Creates a successful result.
  const factory Result.success(T value) = Success<T>;

  /// Creates a failed result.
  const factory Result.failure(AppError error) = Failure<T>;

  /// Pattern-match on the result.
  R when<R>({
    required R Function(T value) success,
    required R Function(AppError error) failure,
  });
}

/// Successful result containing a value.
class Success<T> extends Result<T> {
  const Success(this.value);

  final T value;

  @override
  R when<R>({
    required R Function(T value) success,
    required R Function(AppError error) failure,
  }) =>
      success(value);
}

/// Failed result containing an error.
class Failure<T> extends Result<T> {
  const Failure(this.error);

  final AppError error;

  @override
  R when<R>({
    required R Function(T value) success,
    required R Function(AppError error) failure,
  }) =>
      failure(error);
}
