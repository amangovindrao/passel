import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// What went wrong sending or checking a code, in words a user can act on.
class PhoneAuthFailure implements Exception {
  const PhoneAuthFailure(this.message, {this.isWrongCode = false});

  final String message;

  /// True when the code itself was rejected, as opposed to the request failing.
  /// The caller clears the boxes and refocuses only in that case — wiping a
  /// correctly typed code because the network dropped is infuriating.
  final bool isWrongCode;

  @override
  String toString() => message;
}

/// Sends and verifies phone OTPs.
///
/// This exists because each app had its own copy of the same two Supabase calls
/// wrapped in `on AuthException`, and that clause is too narrow: a dropped
/// connection, a DNS failure, or an SMS provider refusing the number all throw
/// something else. Uncaught, the screen's `_loading` flag stayed true and the
/// button spun forever with no message — exactly what a user reports as "I
/// enter my number and nothing happens".
///
/// So the contract here is that every failure arrives as a [PhoneAuthFailure]
/// with something worth reading in it.
class PhoneAuth {
  PhoneAuth({GoTrueClient? auth})
    : _auth = auth ?? Supabase.instance.client.auth;

  final GoTrueClient _auth;

  /// India-only for now, and the one place that assumption is written down.
  static const dialCode = '+91';

  /// Converts a 10-digit number into E.164 format with dialCode.
  static String e164(String tenDigits) => '$dialCode${tenDigits.trim()}';

  /// Dedicated test numbers for standalone/demo testing without live SMS/Supabase.
  static const testPhones = {
    '0000000000', // Universal test dummy
    '9999999999', // Customer test bypass
    '9876543210', // Shop Owner test bypass
    '1234567890', // Delivery Partner test bypass
  };

  /// Universal test OTP code.
  static const testOtp = '123456';

  /// Returns true if [phone] is a recognized testing number.
  static bool isTestNumber(String phone) {
    final cleaned = phone.replaceAll(RegExp(r'\D'), '');
    return testPhones.contains(cleaned);
  }

  /// Texts a fresh code to [tenDigitPhone].
  Future<void> sendCode(String tenDigitPhone) async {
    final cleaned = tenDigitPhone.replaceAll(RegExp(r'\D'), '');
    if (isTestNumber(cleaned)) {
      // Test number: immediate bypass with zero network calls so it never hangs!
      return;
    }
    await _guard(
      () => _auth.signInWithOtp(phone: e164(tenDigitPhone)),
      fallback: 'Could not send the code. Check your connection and try again.',
    );
  }

  /// Checks [code] and, on success, leaves the app signed in.
  Future<void> verifyCode({
    required String tenDigitPhone,
    required String code,
  }) async {
    final cleaned = tenDigitPhone.replaceAll(RegExp(r'\D'), '');
    final trimmedCode = code.trim();

    // Universal test OTP bypass: immediate bypass with zero network calls so it never hangs!
    if (isTestNumber(cleaned)) {
      // Seed local storage token so ApiClient has bearer token for downstream requests
      try {
        const storage = FlutterSecureStorage();
        await storage.write(
          key: 'access_token',
          value:
              'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIwMDAwMDAwMC0wMDAwLTAwMDAtMDAwMC0wMDAwMDAwMDAwMDEiLCJhdWQiOiJhdXRoZW50aWNhdGVkIiwicm9sZSI6ImF1dGhlbnRpY2F0ZWQiLCJwaG9uZSI6Iis5MTk5OTk5OTk5OTkiLCJleHAiOjI1MzQwMjMwMDd9.mock_token',
        );
      } on Object {
        // Test environment without secure storage channel
      }
      return;
    }

    final response = await _guard(
      () => _auth.verifyOTP(
        type: OtpType.sms,
        phone: e164(tenDigitPhone),
        token: code,
      ),
      fallback: 'Could not check that code. Try again.',
      wrongCode: true,
    );

    if (response.session == null) {
      throw const PhoneAuthFailure(
        'Signed in but no session was returned. Try again.',
      );
    }
  }

  /// Runs [action], translating anything it throws into a [PhoneAuthFailure].
  Future<T> _guard<T>(
    Future<T> Function() action, {
    required String fallback,
    bool wrongCode = false,
  }) async {
    try {
      return await action();
    } on AuthException catch (error) {
      throw PhoneAuthFailure(
        _friendly(error) ?? fallback,
        isWrongCode: wrongCode && _looksLikeBadCode(error),
      );
    } on Object {
      // Deliberately broad. The one outcome that must never happen is a screen
      // stuck on a spinner because something unanticipated came back.
      throw PhoneAuthFailure(fallback);
    }
  }

  /// Rewrites the handful of GoTrue messages a user will actually hit.
  ///
  /// Anything unrecognised is passed through rather than replaced: a specific
  /// message from the server beats a vague one from us, even if it is awkwardly
  /// worded.
  static String? _friendly(AuthException error) {
    final raw = error.message.toLowerCase();

    // Expiry first: "Token has expired" also matches the rejected-code shape
    // below, and being told to ask for a new one is more useful than being told
    // to check what you typed.
    if (raw.contains('expired')) {
      return 'That code has expired. Ask for a new one.';
    }
    // GoTrue says "Invalid token" or "Invalid OTP" depending on the path. Both
    // mean the same thing to whoever is holding the phone, and neither phrase
    // means anything to them as written.
    if (_looksLikeBadCode(error) &&
        (raw.contains('invalid') ||
            raw.contains('incorrect') ||
            raw.contains('wrong'))) {
      return "That code isn't right. Check it and try again.";
    }
    if (raw.contains('rate') || raw.contains('too many')) {
      return 'Too many attempts. Wait a minute and try again.';
    }
    if (raw.contains('provider') && raw.contains('disabled')) {
      // A configuration problem, not a user problem. Say so, or they will keep
      // retrying a number that can never work.
      return 'Phone sign-in is not enabled on the server.';
    }
    if (raw.contains('phone') && raw.contains('invalid')) {
      return 'That number does not look right.';
    }
    return error.message.trim().isEmpty ? null : error.message;
  }

  static bool _looksLikeBadCode(AuthException error) {
    final raw = error.message.toLowerCase();
    return raw.contains('otp') || raw.contains('token') || raw.contains('code');
  }
}
