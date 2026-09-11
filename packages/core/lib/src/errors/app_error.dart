/// Centralized error types for the Paasel platform.
sealed class AppError implements Exception {
  const AppError({required this.message, this.stackTrace});

  final String message;
  final StackTrace? stackTrace;

  @override
  String toString() => 'AppError: $message';
}

/// An error from the network/API layer.
class NetworkError extends AppError {
  const NetworkError({
    required super.message,
    super.stackTrace,
    this.statusCode,
  });

  final int? statusCode;
}

/// An error when the user is not authenticated or the session expired.
class AuthError extends AppError {
  const AuthError({required super.message, super.stackTrace});
}

/// A server-side validation error.
class ValidationError extends AppError {
  const ValidationError({
    required super.message,
    super.stackTrace,
    this.fieldErrors = const {},
  });

  final Map<String, String> fieldErrors;
}

/// An unexpected/unknown error.
class UnexpectedError extends AppError {
  const UnexpectedError({required super.message, super.stackTrace});
}
