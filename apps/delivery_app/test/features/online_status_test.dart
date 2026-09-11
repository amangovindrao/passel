import 'package:delivery_app/src/providers/rider_models.dart';
import 'package:delivery_app/src/providers/rider_providers.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/stubs.dart';

const _onlinePath = '/delivery-partners/online';

OnlineStatusNotifier _notifier({
  required Map<String, StubResponse> responses,
  required StubLocationReporter reporter,
}) {
  return OnlineStatusNotifier(
    client: stubApiClient(responses),
    reporter: reporter,
  );
}

void main() {
  test('going online starts the location loop', () async {
    final reporter = StubLocationReporter(client: stubApiClient(const {}));
    final notifier = _notifier(
      responses: const {
        _onlinePath: StubResponse(200, {'is_online': true}),
      },
      reporter: reporter,
    );

    await notifier.goOnline();

    expect(notifier.state.isOnline, isTrue);
    expect(notifier.state.busy, isFalse);
    expect(
      reporter.isRunning,
      isTrue,
      reason: 'pings must actually be flowing',
    );
  });

  test('a 403 for unapproved KYC leaves the rider offline, unsubscribed', () {
    final reporter = StubLocationReporter(client: stubApiClient(const {}));
    final notifier = _notifier(
      responses: {
        _onlinePath: StubResponse.error(
          403,
          'kyc_not_approved',
          'Your account is still being verified',
        ),
      },
      reporter: reporter,
    );

    return notifier.goOnline().then((_) {
      expect(notifier.state.isOnline, isFalse);
      expect(
        notifier.state.blockedReason,
        'Your account is still being verified',
        reason: "the server's own wording must reach the rider",
      );
      expect(reporter.startCalls, 0);
    });
  });

  test(
    'if the location loop cannot start, the server is rolled back to offline',
    () async {
      final reporter = StubLocationReporter(
        client: stubApiClient(const {}),
        failOnStart: true,
      );
      final client = stubApiClient(const {
        _onlinePath: StubResponse(200, {'is_online': true}),
      });
      final notifier = OnlineStatusNotifier(client: client, reporter: reporter);

      await notifier.goOnline();

      // Never leave the server believing someone is available while nothing is
      // reporting — that is precisely the stuck state the sweep exists to fix.
      expect(notifier.state.isOnline, isFalse);
      expect(
        notifier.state.blockedReason,
        'Allow background location to go online',
      );
      expect(reporter.isRunning, isFalse);
    },
  );

  test('going offline stops the location loop', () async {
    final reporter = StubLocationReporter(client: stubApiClient(const {}));
    final notifier = _notifier(
      responses: const {
        _onlinePath: StubResponse(200, {'is_online': true}),
      },
      reporter: reporter,
    );
    await notifier.goOnline();

    await notifier.goOffline();

    expect(notifier.state.isOnline, isFalse);
    expect(reporter.stopCalls, 1);
  });

  test(
    'a 409 mid-delivery keeps the rider online and surfaces the reason',
    () async {
      final reporter = StubLocationReporter(client: stubApiClient(const {}));

      // Online succeeds, then offline is refused.
      final notifier = OnlineStatusNotifier(
        client: stubApiClient(const {
          _onlinePath: StubResponse(200, {'is_online': true}),
        }),
        reporter: reporter,
      );
      await notifier.goOnline();
      expect(notifier.state.isOnline, isTrue);

      final refusing = OnlineStatusNotifier(
        client: stubApiClient({
          _onlinePath: StubResponse.error(
            409,
            'delivery_in_progress',
            'Finish your current delivery first',
          ),
        }),
        reporter: reporter,
      )..hydrate(const RiderData(exists: true, isOnline: true));

      await refusing.goOffline();

      expect(
        refusing.state.isOnline,
        isTrue,
        reason: 'the UI must not drift from the server',
      );
      expect(
        refusing.state.blockedReason,
        'Finish your current delivery first',
      );
      // Pings keep flowing: the delivery is still happening.
      expect(reporter.isRunning, isTrue);
    },
  );

  test('hydrate adopts the server view and reconciles a stale flag', () async {
    final reporter = StubLocationReporter(client: stubApiClient(const {}));
    final notifier = _notifier(responses: const {}, reporter: reporter)
      ..hydrate(const RiderData(exists: true, isOnline: true));

    expect(notifier.state.isOnline, isTrue);
    // Server said online but nothing was reporting, so the loop is started
    // rather than leaving a claim on screen that is not true.
    await Future<void>.delayed(Duration.zero);
    expect(reporter.startCalls, 1);
  });

  test('clearBlockedReason drops a consumed message', () async {
    final reporter = StubLocationReporter(client: stubApiClient(const {}));
    final notifier = _notifier(
      responses: {
        _onlinePath: StubResponse.error(403, 'kyc_not_approved', 'Not yet'),
      },
      reporter: reporter,
    );

    await notifier.goOnline();
    expect(notifier.state.blockedReason, 'Not yet');

    notifier.clearBlockedReason();
    expect(notifier.state.blockedReason, isNull);
  });
}
