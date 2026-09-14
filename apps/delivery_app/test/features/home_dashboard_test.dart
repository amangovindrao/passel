import 'package:core/core.dart';
import 'package:delivery_app/src/features/home/home_screen.dart';
import 'package:delivery_app/src/features/home/widgets/go_online_toggle.dart';
import 'package:delivery_app/src/providers/rider_models.dart';
import 'package:delivery_app/src/providers/rider_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

import '../support/stubs.dart';

const _approvedRider = RiderData(
  exists: true,
  name: 'Ravi K',
  kycStatus: 'approved',
  vehicleType: 'bike',
  completedToday: 4,
);

const _activeAssignment = ActiveAssignment(
  assignmentId: 'a1',
  orderId: 'o1',
  shopName: 'Corner Store',
  orderStatus: 'PARTNER_ASSIGNED',
);

/// The real notifier, wired to a stub adapter that refuses to go offline the
/// way the server does mid-delivery. Nothing about the refusal handling is
/// simulated — only the transport is.
OnlineStatusNotifier _refusingNotifier(StubLocationReporter reporter) {
  return OnlineStatusNotifier(
    client: stubApiClient({
      '/delivery-partners/online': StubResponse.error(
        409,
        'delivery_in_progress',
        'Finish your current delivery first',
      ),
    }),
    reporter: reporter,
  )..hydrate(const RiderData(exists: true, isOnline: true));
}

ProviderContainer _container({
  ActiveAssignment? assignment,
  LocationAccess access = LocationAccess.always,
  OnlineStatusNotifier Function(Ref ref)? onlineOverride,
}) {
  final container = ProviderContainer(
    overrides: [
      riderDataProvider.overrideWith((ref) async => _approvedRider),
      walletDataProvider.overrideWith(
        (ref) async => const WalletData(
          walletId: 'w1',
          balancePaise: 45000,
          ownerType: 'delivery_partner',
        ),
      ),
      locationReporterProvider.overrideWith(
        (ref) => StubLocationReporter(
          client: stubApiClient(const {}),
          access: access,
        ),
      ),
      locationAccessProvider.overrideWith(
        (ref) => _StubAccessNotifier(
          ref.watch(locationReporterProvider) as StubLocationReporter,
          access,
        ),
      ),
      if (onlineOverride != null)
        onlineStatusProvider.overrideWith(onlineOverride),
    ],
  );
  addTearDown(container.dispose);
  if (assignment != null) {
    container.read(activeAssignmentProvider.notifier).state = assignment;
  }
  return container;
}

class _StubAccessNotifier extends LocationAccessNotifier {
  _StubAccessNotifier(super.reporter, this._value);

  final LocationAccess _value;

  @override
  Future<void> refresh() async => state = _value;
}

Widget _subject(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(theme: AppTheme.dark(), home: const RiderHomeScreen()),
  );
}

void main() {
  testWidgets(
    'locked "On a delivery" card replaces the toggle when an assignment is '
    'accepted',
    (tester) async {
      final container = _container(assignment: _activeAssignment);

      await tester.pumpWidget(_subject(container));
      await tester.pump();

      // The whole control is gone, not merely disabled — there is nothing to
      // tap and therefore nothing to wonder about.
      expect(find.byType(GoOnlineToggle), findsNothing);
      expect(find.byKey(const ValueKey('go-online-toggle')), findsNothing);

      expect(find.byKey(const ValueKey('on-a-delivery-card')), findsOneWidget);
      expect(find.text('On a delivery'), findsOneWidget);
      expect(find.text('Corner Store'), findsOneWidget);
      expect(find.text('Heading to pickup'), findsOneWidget);
    },
  );

  testWidgets('toggle is shown when there is no active assignment', (
    tester,
  ) async {
    final container = _container();

    await tester.pumpWidget(_subject(container));
    await tester.pump();

    expect(find.byType(GoOnlineToggle), findsOneWidget);
    expect(find.byKey(const ValueKey('on-a-delivery-card')), findsNothing);
  });

  testWidgets(
    'a 409 refusal surfaces via AppSnackbar and leaves the toggle on',
    (tester) async {
      final reporter = StubLocationReporter(client: stubApiClient(const {}));
      final container = _container(
        onlineOverride: (ref) => _refusingNotifier(reporter),
      );

      await tester.pumpWidget(_subject(container));
      await tester.pump();

      expect(container.read(onlineStatusProvider).isOnline, isTrue);

      await tester.tap(find.byKey(const ValueKey('go-online-toggle')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // The refusal is shown to the rider, not swallowed.
      expect(find.byType(AppSnackbar), findsOneWidget);
      expect(find.text('Finish your current delivery first'), findsOneWidget);

      // And the toggle has not drifted away from what the server believes.
      expect(container.read(onlineStatusProvider).isOnline, isTrue);
      final toggle = tester.widget<GoOnlineToggle>(find.byType(GoOnlineToggle));
      expect(toggle.isOnline, isTrue);
    },
  );

  testWidgets('foreground-only location keeps the toggle disabled', (
    tester,
  ) async {
    final container = _container(access: LocationAccess.whileInUseOnly);

    await tester.pumpWidget(_subject(container));
    await tester.pump();

    // Distinct state with its own explanation and a route to settings — not
    // silently treated as "granted", which would break tracking on lock.
    expect(
      find.byKey(const ValueKey('location-foreground-only-card')),
      findsOneWidget,
    );
    expect(find.text('Open settings'), findsOneWidget);

    final toggle = tester.widget<GoOnlineToggle>(find.byType(GoOnlineToggle));
    expect(toggle.onPressed, isNull);
    expect(
      find.byKey(const ValueKey('toggle-disabled-reason')),
      findsOneWidget,
    );
  });

  testWidgets('denied location shows its own card, not the explainer', (
    tester,
  ) async {
    final container = _container(access: LocationAccess.denied);

    await tester.pumpWidget(_subject(container));
    await tester.pump();

    expect(find.byKey(const ValueKey('location-denied-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('location-explainer-card')), findsNothing);

    final toggle = tester.widget<GoOnlineToggle>(find.byType(GoOnlineToggle));
    expect(toggle.onPressed, isNull);
  });

  testWidgets(
    'explainer card leads with the background reason before the OS dialog',
    (tester) async {
      final container = _container(access: LocationAccess.unknown);

      await tester.pumpWidget(_subject(container));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('location-explainer-card')),
        findsOneWidget,
      );
      expect(find.textContaining('in the background'), findsOneWidget);
      expect(find.textContaining('Allow all the time'), findsOneWidget);
    },
  );

  testWidgets("today's snapshot shows a count and no earnings figure", (
    tester,
  ) async {
    final container = _container();

    await tester.pumpWidget(_subject(container));
    await tester.pump();

    expect(find.text('4 deliveries done'), findsOneWidget);
    // Money belongs on the wallet screen; a partial number here would mislead.
    expect(find.textContaining('₹'), findsNothing);
  });

  test('LocationAccess only lets "always" go online', () {
    expect(LocationAccess.always.canGoOnline, isTrue);
    expect(LocationAccess.whileInUseOnly.canGoOnline, isFalse);
    expect(LocationAccess.denied.canGoOnline, isFalse);
    expect(LocationAccess.unknown.canGoOnline, isFalse);
  });
}
