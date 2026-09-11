import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

/// `String.fromEnvironment` is resolved at compile time, so under a plain
/// `flutter test` — no `--dart-define` anywhere — every value here is empty.
/// That makes this file the exact shape of the build that broke: it can only
/// assert on which variables are treated as required, which is precisely the
/// thing that regressed.
void main() {
  group('EnvConfig.validate', () {
    test('refuses to start without the three variables it truly needs', () {
      expect(EnvConfig.validate, throwsA(isA<StateError>()));

      final message = _messageFromValidate();
      expect(message, contains('API_BASE_URL'));
      expect(message, contains('SUPABASE_URL'));
      expect(message, contains('SUPABASE_ANON_KEY'));
    });

    test('does not require SENTRY_DSN', () {
      // This ran before runApp in all three apps. Requiring it meant any build
      // without a Sentry project — every local and CI build — threw here and
      // showed a white screen with no message anywhere on the device.
      expect(_messageFromValidate(), isNot(contains('SENTRY_DSN')));
    });

    test('does not require GOOGLE_MAPS_API_KEY', () {
      // Costs one blank map tile. Never a reason to refuse to launch.
      expect(_messageFromValidate(), isNot(contains('GOOGLE_MAPS_API_KEY')));
    });

    test('names every missing variable at once, not just the first', () {
      // A validator that stops at the first problem turns one bad build into
      // three round trips.
      final message = _messageFromValidate();
      expect(message.split(',').length, greaterThanOrEqualTo(3));
    });
  });

  group('optional capability flags', () {
    test('report absent when unconfigured', () {
      expect(EnvConfig.hasSentry, isFalse);
      expect(EnvConfig.hasMaps, isFalse);
    });
  });

  group('flavor', () {
    test('falls back to dev so a build is never unlabelled', () {
      expect(EnvConfig.flavor, 'dev');
    });
  });
}

/// The message from a failing [EnvConfig.validate], for asserting on its
/// contents rather than merely that it threw.
///
/// Catching an Error is normally wrong, but the contract under test is that
/// this particular StateError names the right variables — and the only way to
/// read its message is to catch it.
String _messageFromValidate() {
  try {
    EnvConfig.validate();
    // ignore: avoid_catching_errors — the message is the thing under test
  } on StateError catch (error) {
    return error.message;
  }
  fail('EnvConfig.validate() was expected to throw with no dart-defines set');
}
