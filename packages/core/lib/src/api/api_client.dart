import 'package:core/src/api/auth_interceptor.dart';
import 'package:core/src/env/env_config.dart';
import 'package:core/src/errors/app_error.dart';
import 'package:core/src/errors/result.dart';
import 'package:dio/dio.dart';

/// Dio-based API client with authentication interceptor.
class ApiClient {
  ApiClient({Dio? dio, AuthInterceptor? authInterceptor})
    : _authInterceptor = authInterceptor ?? AuthInterceptor(),
      _dio = dio ?? Dio() {
    // An explicitly configured baseUrl wins. Overwriting it unconditionally
    // meant a caller-supplied Dio was silently pointed at the compile-time
    // value, which is empty outside a --dart-define build.
    final base = _dio.options.baseUrl.isNotEmpty
        ? _dio.options.baseUrl
        : EnvConfig.apiBaseUrl;
    _dio.options
      ..baseUrl = base
      ..connectTimeout = const Duration(seconds: 15)
      ..receiveTimeout = const Duration(seconds: 15)
      ..headers = <String, dynamic>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };
    _dio.interceptors.add(_authInterceptor);
  }

  final Dio _dio;
  final AuthInterceptor _authInterceptor;

  /// Access the auth interceptor for token management.
  AuthInterceptor get authInterceptor => _authInterceptor;

  /// Perform a GET request wrapped in [Result].
  Future<Result<T>> get<T>(
    String path, {
    required T Function(dynamic data) fromJson,
    Map<String, dynamic>? queryParameters,
  }) async {
    return _request(
      () => _dio.get<dynamic>(path, queryParameters: queryParameters),
      fromJson: fromJson,
    );
  }

  /// Perform a POST request wrapped in [Result].
  Future<Result<T>> post<T>(
    String path, {
    required T Function(dynamic data) fromJson,
    dynamic data,
  }) async {
    return _request(
      () => _dio.post<dynamic>(path, data: data),
      fromJson: fromJson,
    );
  }

  /// Perform a PUT request wrapped in [Result].
  Future<Result<T>> put<T>(
    String path, {
    required T Function(dynamic data) fromJson,
    dynamic data,
  }) async {
    return _request(
      () => _dio.put<dynamic>(path, data: data),
      fromJson: fromJson,
    );
  }

  /// Perform a PATCH request wrapped in [Result].
  Future<Result<T>> patch<T>(
    String path, {
    required T Function(dynamic data) fromJson,
    dynamic data,
  }) async {
    return _request(
      () => _dio.patch<dynamic>(path, data: data),
      fromJson: fromJson,
    );
  }

  /// Perform a DELETE request wrapped in [Result].
  Future<Result<T>> delete<T>(
    String path, {
    required T Function(dynamic data) fromJson,
  }) async {
    return _request(() => _dio.delete<dynamic>(path), fromJson: fromJson);
  }

  Future<Result<T>> _request<T>(
    Future<Response<dynamic>> Function() request, {
    required T Function(dynamic data) fromJson,
  }) async {
    try {
      final response = await request();
      return Result.success(fromJson(response.data));
    } on DioException catch (e, st) {
      return Result.failure(
        NetworkError(
          message: _messageFrom(e),
          statusCode: e.response?.statusCode,
          stackTrace: st,
        ),
      );
    } on Object catch (e, st) {
      return Result.failure(
        UnexpectedError(message: e.toString(), stackTrace: st),
      );
    }
  }

  /// Prefers the API's own error message over Dio's generic wording.
  ///
  /// The backend answers failures with `{"error": {"code", "message"}}`, and
  /// that message is usually written to be read by the user — "Finish your
  /// current delivery first" is far more use than "The request returned an
  /// invalid status code of 409". Falls back to Dio's text when the body is
  /// missing or shaped differently, e.g. a genuine transport failure.
  static String _messageFrom(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      final error = data['error'];
      if (error is Map) {
        final message = error['message'];
        if (message is String && message.trim().isNotEmpty) return message;
      }
      final detail = data['detail'];
      if (detail is String && detail.trim().isNotEmpty) return detail;
    }
    return e.message ?? 'Network request failed';
  }
}
