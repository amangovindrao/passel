// `hide User`: core exports its own User model and gotrue exports another. The
// one this file needs is gotrue's, to build a Session.
import 'package:core/core.dart' hide User;
import 'package:customer_app/src/features/onboarding/otp_screen.dart';
import 'package:customer_app/src/providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ui_kit/ui_kit.dart';

class _MockGoTrueClient extends Mock implements GoTrueClient {}

void main() {
  late _MockGoTrueClient auth;
  late PhoneAuth phoneAuth;

  setUp(() {
    auth = _MockGoTrueClient();
    phoneAuth = PhoneAuth(auth: auth);
  });

  /// A verify result that actually carries a session.
  ///
  /// This matters: everything after this screen reads the access token off the
  /// session, so a verify that returns none is a failure however encouraging
  /// the status code looked.
  AuthResponse verified() => AuthResponse(
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

  void stubVerify({Object? throws, AuthResponse? response}) {
    final call = when(
      () => auth.verifyOTP(
        phone: any(named: 'phone'),
        token: any(named: 'token'),
        type: OtpType.sms,
      ),
    );
    if (throws != null) {
      call.thenThrow(throws);
    } else {
      call.thenAnswer((_) async => response ?? verified());
    }
  }

  Widget subject() {
    final router = GoRouter(
      initialLocation: '/otp',
      routes: [
        GoRoute(
          path: '/otp',
          builder: (_, __) => const OtpScreen(phone: '9999000001'),
        ),
        GoRoute(
          path: '/name',
          builder: (_, __) =>
              const Scaffold(body: Center(child: Text('name step'))),
        ),
      ],
    );
    return ProviderScope(
      overrides: [phoneAuthProvider.overrideWithValue(phoneAuth)],
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    );
  }

  Finder box(int i) => find.byKey(ValueKey('otp-box-$i'));

  Future<void> enterCode(WidgetTester tester, {int digits = 6}) async {
    for (var i = 0; i < digits; i++) {
      await tester.enterText(box(i), '${i + 1}');
      await tester.pump();
    }
  }

  testWidgets('digits land in the box they were typed into', (tester) async {
    stubVerify();
    await tester.pumpWidget(subject());

    await enterCode(tester);

    for (var i = 0; i < 6; i++) {
      expect(tester.widget<TextField>(box(i)).controller!.text, '${i + 1}');
    }
  });

  testWidgets('the sixth digit auto-submits without tapping anything', (
    tester,
  ) async {
    stubVerify();
    await tester.pumpWidget(subject());

    // Five digits is not a complete code, so nothing should be sent yet.
    await enterCode(tester, digits: 5);
    verifyNever(
      () => auth.verifyOTP(
        phone: any(named: 'phone'),
        token: any(named: 'token'),
        type: OtpType.sms,
      ),
    );

    await tester.enterText(box(5), '6');
    await tester.pump();

    verify(
      () => auth.verifyOTP(
        phone: '+919999000001',
        token: '123456',
        type: OtpType.sms,
      ),
    ).called(1);
  });

  testWidgets('a verified code moves on to the name step', (tester) async {
    stubVerify();
    await tester.pumpWidget(subject());

    await enterCode(tester);
    await tester.pumpAndSettle();

    expect(find.text('name step'), findsOneWidget);
  });

  testWidgets('a wrong code says so instead of failing silently', (
    tester,
  ) async {
    stubVerify(throws: const AuthException('Invalid token'));
    await tester.pumpWidget(subject());

    await enterCode(tester);
    await tester.pump();

    expect(find.byKey(const ValueKey('otp-error')), findsOneWidget);
    expect(find.textContaining("isn't right"), findsOneWidget);
    // Still on the OTP screen — a bad code must not advance the flow.
    expect(find.text('name step'), findsNothing);
  });

  testWidgets('a wrong code clears the boxes ready for another try', (
    tester,
  ) async {
    stubVerify(throws: const AuthException('Invalid token'));
    await tester.pumpWidget(subject());

    await enterCode(tester);
    await tester.pump();

    expect(tester.widget<TextField>(box(0)).controller!.text, '');
  });

  testWidgets('an expired code points the user at resend', (tester) async {
    stubVerify(throws: const AuthException('Token has expired'));
    await tester.pumpWidget(subject());

    await enterCode(tester);
    await tester.pump();

    expect(find.textContaining('expired'), findsOneWidget);
  });

  testWidgets('a network failure is reported and keeps the typed code', (
    tester,
  ) async {
    // The case the old `on AuthException` clause missed entirely: the screen
    // used to sit on a spinner with nothing on screen to explain it.
    stubVerify(throws: Exception('SocketException: host lookup failed'));
    await tester.pumpWidget(subject());

    await enterCode(tester);
    await tester.pump();

    expect(find.byKey(const ValueKey('otp-error')), findsOneWidget);
    expect(find.text('name step'), findsNothing);
    // Not the user's fault, so their digits stay put.
    expect(tester.widget<TextField>(box(0)).controller!.text, '1');
  });

  testWidgets('a verify that returns no session is treated as a failure', (
    tester,
  ) async {
    stubVerify(response: AuthResponse());
    await tester.pumpWidget(subject());

    await enterCode(tester);
    await tester.pump();

    // Advancing here would break on the next screen instead, where the API
    // client would find no token to send.
    expect(find.text('name step'), findsNothing);
    expect(find.byKey(const ValueKey('otp-error')), findsOneWidget);
  });
}
