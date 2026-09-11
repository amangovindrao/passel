// `hide User`: core exports its own User model and gotrue exports another. The
// one this file needs is gotrue's, to build a Session.
import 'package:core/core.dart' hide User;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MockAuth extends Mock implements GoTrueClient {}

/// The point of [PhoneAuth] is that nothing escapes it untranslated. Each app
/// used to catch only `AuthException`, so anything else left the send button
/// spinning with no message — the failure a user reports as "I type my number
/// and nothing happens". These tests are mostly about that.
void main() {
  late _MockAuth auth;
  late PhoneAuth subject;

  setUp(() {
    auth = _MockAuth();
    subject = PhoneAuth(auth: auth);
  });

  AuthResponse responseWithSession() => AuthResponse(
    session: Session(
      accessToken: 'token',
      tokenType: 'bearer',
      user: User(
        id: 'u1',
        appMetadata: const {},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: DateTime.now().toIso8601String(),
      ),
    ),
  );

  group('phone formatting', () {
    test('adds the dial code once, and trims', () {
      expect(PhoneAuth.e164(' 9900000001 '), '+919900000001');
    });
  });

  group('sendCode', () {
    test('passes the E.164 number through', () async {
      when(
        () => auth.signInWithOtp(phone: any(named: 'phone')),
      ).thenAnswer((_) async {});

      await subject.sendCode('9900000001');

      verify(() => auth.signInWithOtp(phone: '+919900000001')).called(1);
    });

    test('a network failure becomes a readable message, not a hang', () async {
      // Not an AuthException — the case every app used to miss.
      when(
        () => auth.signInWithOtp(phone: any(named: 'phone')),
      ).thenThrow(Exception('SocketException: failed host lookup'));

      await expectLater(
        subject.sendCode('9900000001'),
        throwsA(
          isA<PhoneAuthFailure>().having(
            (e) => e.message,
            'message',
            contains('Could not send the code'),
          ),
        ),
      );
    });

    test('a disabled provider is reported as a server problem', () async {
      // Otherwise a user retries a number that can never work.
      when(
        () => auth.signInWithOtp(phone: any(named: 'phone')),
      ).thenThrow(const AuthException('Phone provider disabled'));

      await expectLater(
        subject.sendCode('9900000001'),
        throwsA(
          isA<PhoneAuthFailure>().having(
            (e) => e.message,
            'message',
            contains('not enabled on the server'),
          ),
        ),
      );
    });

    test('an unrecognised server message is passed through, not swallowed', () {
      when(
        () => auth.signInWithOtp(phone: any(named: 'phone')),
      ).thenThrow(const AuthException('Signups not allowed for this instance'));

      expect(
        subject.sendCode('9900000001'),
        throwsA(
          isA<PhoneAuthFailure>().having(
            (e) => e.message,
            'message',
            'Signups not allowed for this instance',
          ),
        ),
      );
    });
  });

  group('verifyCode', () {
    test('succeeds when a session comes back', () async {
      when(
        () => auth.verifyOTP(
          type: OtpType.sms,
          phone: any(named: 'phone'),
          token: any(named: 'token'),
        ),
      ).thenAnswer((_) async => responseWithSession());

      await subject.verifyCode(tenDigitPhone: '9900000001', code: '123456');

      verify(
        () => auth.verifyOTP(
          type: OtpType.sms,
          phone: '+919900000001',
          token: '123456',
        ),
      ).called(1);
    });

    test('a verify with no session is a failure, not a success', () async {
      // Everything after this reads the access token off the session, so a
      // "verified" state without one would break on the next screen instead.
      when(
        () => auth.verifyOTP(
          type: OtpType.sms,
          phone: any(named: 'phone'),
          token: any(named: 'token'),
        ),
      ).thenAnswer((_) async => AuthResponse());

      await expectLater(
        subject.verifyCode(tenDigitPhone: '9900000001', code: '123456'),
        throwsA(isA<PhoneAuthFailure>()),
      );
    });

    test('a rejected code is flagged so the boxes can be cleared', () async {
      when(
        () => auth.verifyOTP(
          type: OtpType.sms,
          phone: any(named: 'phone'),
          token: any(named: 'token'),
        ),
      ).thenThrow(const AuthException('Invalid OTP'));

      await expectLater(
        subject.verifyCode(tenDigitPhone: '9900000001', code: '000000'),
        throwsA(
          isA<PhoneAuthFailure>()
              .having((e) => e.isWrongCode, 'isWrongCode', isTrue)
              .having((e) => e.message, 'message', contains("isn't right")),
        ),
      );
    });

    test('an expired code says to ask for a new one', () async {
      when(
        () => auth.verifyOTP(
          type: OtpType.sms,
          phone: any(named: 'phone'),
          token: any(named: 'token'),
        ),
      ).thenThrow(const AuthException('Token has expired'));

      await expectLater(
        subject.verifyCode(tenDigitPhone: '9900000001', code: '123456'),
        throwsA(
          isA<PhoneAuthFailure>().having(
            (e) => e.message,
            'message',
            contains('expired'),
          ),
        ),
      );
    });

    test('a network failure does not clear a correctly typed code', () async {
      when(
        () => auth.verifyOTP(
          type: OtpType.sms,
          phone: any(named: 'phone'),
          token: any(named: 'token'),
        ),
      ).thenThrow(Exception('connection reset'));

      await expectLater(
        subject.verifyCode(tenDigitPhone: '9900000001', code: '123456'),
        throwsA(
          isA<PhoneAuthFailure>().having(
            (e) => e.isWrongCode,
            'isWrongCode',
            isFalse,
          ),
        ),
      );
    });

    test('rate limiting is named rather than shown as a generic error', () {
      when(
        () => auth.verifyOTP(
          type: OtpType.sms,
          phone: any(named: 'phone'),
          token: any(named: 'token'),
        ),
      ).thenThrow(const AuthException('Too many requests'));

      expect(
        subject.verifyCode(tenDigitPhone: '9900000001', code: '123456'),
        throwsA(
          isA<PhoneAuthFailure>().having(
            (e) => e.message,
            'message',
            contains('Too many attempts'),
          ),
        ),
      );
    });
  });
}
