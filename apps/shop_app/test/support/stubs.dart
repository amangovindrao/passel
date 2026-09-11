import 'dart:convert';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shop_app/src/services/packing_photo_uploader.dart';
// `show` rather than a bare import: supabase_flutter re-exports postgrest,
// which also declares a `Headers`, and it collides with Dio's.
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

/// Serves canned HTTP responses so the real [ApiClient] and its error mapping
/// are exercised, rather than stubbed past.
///
/// Ported from delivery_app's harness. Matching on the tail of the path means a
/// test declares the endpoint it cares about and ignores the base URL.
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

    // Longest match wins: '/orders/x' and '/orders/x/accept' both end with the
    // former, and a shorter accidental match would answer the wrong call.
    final matches =
        responses.entries
            .where((entry) => options.path.endsWith(entry.key))
            .toList()
          ..sort((a, b) => b.key.length.compareTo(a.key.length));
    final stub = matches.isEmpty
        ? const StubResponse(200, {'status': 'ok'})
        : matches.first.value;

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
  final Object body;
}

/// Passes requests straight through.
///
/// The real interceptor reads the token from the live Supabase session, which
/// needs platform channels that do not exist in a plain unit test.
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

/// An [ApiClient] wired to a stub adapter, plus the adapter itself so a test
/// can assert on which paths were called.
({ApiClient client, StubHttpAdapter adapter}) stubApi(
  Map<String, StubResponse> responses,
) {
  final adapter = StubHttpAdapter(responses);
  final dio = Dio(BaseOptions(baseUrl: 'https://stub.paasel.test'))
    ..httpClientAdapter = adapter;
  return (
    client: ApiClient(dio: dio, authInterceptor: StubAuthInterceptor()),
    adapter: adapter,
  );
}

class _MockSupabaseClient extends Mock implements SupabaseClient {}

/// A [PackingPhotoUploader] that never touches the camera or a storage bucket.
///
/// Subclasses the real thing rather than defining a parallel interface, so a
/// signature change breaks compilation here instead of silently diverging. The
/// mock client satisfies the constructor; every method that would reach it is
/// overridden.
class StubPackingPhotoUploader extends PackingPhotoUploader {
  StubPackingPhotoUploader({this.url = 'https://stub.test/packed.jpg'})
    : super(client: _MockSupabaseClient());

  /// What the upload resolves to. Null models the shopkeeper backing out of the
  /// picker, which must not read as a failure.
  String? url;

  /// Set to raise a failure instead of returning.
  String? failWith;

  int calls = 0;

  @override
  Future<String?> pickAndUpload({
    required String orderId,
    ImageSource source = ImageSource.camera,
  }) async {
    calls++;
    final failure = failWith;
    if (failure != null) throw PackingPhotoFailure(failure);
    return url;
  }
}
