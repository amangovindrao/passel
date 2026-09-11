import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Resolves the bearer token for an outgoing request.
///
/// Returns null when there is no session, in which case no Authorization
/// header is attached and the API answers 401 — which is correct.
typedef TokenResolver = Future<String?> Function();

/// Attaches the caller's Supabase access token to every API request.
///
/// Supabase owns the session: it issues the JWT at phone-OTP login, persists
/// it, and refreshes it. The backend verifies that same token. So the token is
/// read live from the Supabase client on each request rather than copied into
/// storage, because a copy goes stale the moment Supabase rotates it — and a
/// stale copy is a 401 that looks like a login bug.
///
/// Secure storage remains a fallback so [saveTokens] keeps working for anything
/// that authenticates outside Supabase.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({FlutterSecureStorage? storage, TokenResolver? tokenResolver})
    : _storage = storage ?? const FlutterSecureStorage(),
      _tokenResolver = tokenResolver;

  final FlutterSecureStorage _storage;
  final TokenResolver? _tokenResolver;

  static const _accessTokenKey = 'access_token';
  static const _refreshTokenKey = 'refresh_token';

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await _currentToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    // Only a rejected token is worth retrying. A 401 carrying an application
    // code — registration_required, say — is a real answer the caller must see,
    // not something a refresh can fix.
    if (err.response?.statusCode != 401 || !_isTokenRejection(err)) {
      handler.next(err);
      return;
    }

    final refreshed = await _refresh();
    if (refreshed == null || refreshed.isEmpty) {
      handler.next(err);
      return;
    }

    try {
      final options = err.requestOptions;
      options.headers['Authorization'] = 'Bearer $refreshed';
      return handler.resolve(await Dio().fetch<dynamic>(options));
    } on Object {
      handler.next(err);
    }
  }

  /// Persist tokens for a non-Supabase login. Unused by the Paasel apps.
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _storage.write(key: _accessTokenKey, value: accessToken);
    await _storage.write(key: _refreshTokenKey, value: refreshToken);
  }

  Future<void> clearTokens() async {
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
  }

  Future<String?> _currentToken() async {
    final resolver = _tokenResolver;
    if (resolver != null) return resolver();

    final supabaseToken = _supabaseAccessToken();
    if (supabaseToken != null && supabaseToken.isNotEmpty) {
      return supabaseToken;
    }
    return _readStored(_accessTokenKey);
  }

  /// Asks Supabase to rotate the session, then hands back the new token.
  Future<String?> _refresh() async {
    try {
      final session = await Supabase.instance.client.auth.refreshSession();
      return session.session?.accessToken;
    } on Object {
      return null;
    }
  }

  static String? _supabaseAccessToken() {
    try {
      return Supabase.instance.client.auth.currentSession?.accessToken;
    } on Object {
      // Supabase not initialised — normal in tests and before startup.
      return null;
    }
  }

  Future<String?> _readStored(String key) async {
    try {
      return await _storage.read(key: key);
    } on Object {
      // No platform channel (unit tests) — treat as no token.
      return null;
    }
  }

  static bool _isTokenRejection(DioException err) {
    final data = err.response?.data;
    if (data is! Map) return true;
    final error = data['error'];
    if (error is! Map) return true;
    return error['code'] == 'invalid_token' ||
        error['code'] == 'not_authenticated';
  }
}
