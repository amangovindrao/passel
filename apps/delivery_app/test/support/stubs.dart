import 'dart:convert';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:delivery_app/src/providers/rider_models.dart';
import 'package:delivery_app/src/services/location_reporter.dart';
import 'package:dio/dio.dart';
import 'package:geolocator/geolocator.dart';

/// A [LocationReporter] that never touches the platform.
///
/// Subclassing the real thing rather than defining a parallel interface keeps
/// the production signatures honest — if one changes, this stops compiling.
class StubLocationReporter extends LocationReporter {
  StubLocationReporter({
    required super.client,
    this.access = LocationAccess.always,
    this.failOnStart = false,
  });

  LocationAccess access;
  bool failOnStart;

  int startCalls = 0;
  int stopCalls = 0;
  bool _running = false;

  @override
  bool get isRunning => _running;

  @override
  Position? get lastPosition => null;

  @override
  Future<void> start() async {
    startCalls++;
    if (failOnStart) {
      throw const LocationPermissionRequired(
        'Allow background location to go online',
      );
    }
    _running = true;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    _running = false;
  }

  @override
  Future<LocationAccess> currentAccess() async => access;

  @override
  Future<LocationAccess> request() async => access;

  @override
  Future<void> openSettings() async {}
}

/// Serves canned HTTP responses so the real [ApiClient] and its error mapping
/// are exercised, rather than stubbed past.
class StubHttpAdapter implements HttpClientAdapter {
  StubHttpAdapter(this.responses);

  /// Keyed by the tail of the request path.
  final Map<String, StubResponse> responses;

  final requestedPaths = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestedPaths.add(options.path);

    final match = responses.entries
        .where((entry) => options.path.endsWith(entry.key))
        .firstOrNull;
    final stub = match?.value ?? const StubResponse(200, {'status': 'ok'});

    return ResponseBody.fromString(
      jsonEncode(stub.body),
      stub.statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class StubResponse {
  const StubResponse(this.statusCode, this.body);

  /// The shape the backend actually returns for a refused request.
  factory StubResponse.error(int statusCode, String code, String message) =>
      StubResponse(statusCode, {
        'error': {'code': code, 'message': message},
      });

  final int statusCode;
  final Map<String, dynamic> body;
}

/// Passes requests straight through.
///
/// The real interceptor reads the token from secure storage, which needs a
/// platform channel that does not exist in a plain unit test.
class StubAuthInterceptor extends AuthInterceptor {
  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async => handler.next(options);

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async => handler.next(err);
}

/// An [ApiClient] wired to a stub adapter.
ApiClient stubApiClient(Map<String, StubResponse> responses) {
  final dio = Dio(BaseOptions(baseUrl: 'https://stub.paasel.test'))
    ..httpClientAdapter = StubHttpAdapter(responses);
  return ApiClient(dio: dio, authInterceptor: StubAuthInterceptor());
}
