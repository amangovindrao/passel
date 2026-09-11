import 'package:core/core.dart';
import 'package:delivery_app/src/features/offers/offer_screen.dart';
import 'package:delivery_app/src/features/offers/widgets/countdown_ring.dart';
import 'package:delivery_app/src/providers/rider_models.dart';
import 'package:delivery_app/src/providers/rider_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

const _freshOffer = RiderOffer(
  assignmentId: 'a1',
  orderId: 'o1',
  kind: OfferKind.fresh,
  shopName: 'Corner Store',
  windowSeconds: 35,
  earningPaise: 4500,
  itemCount: 3,
  distanceToShopMeters: 850,
);

const _detourOffer = RiderOffer(
  assignmentId: 'a2',
  orderId: 'o2',
  kind: OfferKind.batchDetour,
  shopName: 'Fresh Mart',
  windowSeconds: 20,
  earningPaise: 3000,
  itemCount: 2,
  detourMeters: 800,
);

ProviderContainer _container() {
  final container = ProviderContainer(
    overrides: [
      // Keep the alert plumbing silent and offline for tests.
      alertCenterProvider.overrideWith(
        (ref) => AlertCenter(transport: InMemoryAlertTransport()),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Widget _subject(ProviderContainer container, RiderOffer offer) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: AppTheme.dark(),
      home: OfferScreen(offer: offer),
    ),
  );
}

void main() {
  testWidgets(
    'fresh offer auto-dismisses once the 35s countdown reaches zero',
    (tester) async {
      final container = _container();
      container.read(currentOfferProvider.notifier).state = _freshOffer;

      await tester.pumpWidget(_subject(container, _freshOffer));

      expect(find.text('35'), findsOneWidget);
      expect(container.read(currentOfferProvider), isNotNull);

      // Part-way through: still on screen, still holding the offer.
      await tester.pump(const Duration(seconds: 20));
      expect(container.read(currentOfferProvider), isNotNull);

      // Window closes. The server has already moved to the next partner, so
      // this screen clears itself and the rider returns to the dashboard.
      await tester.pump(const Duration(seconds: 15));
      expect(container.read(currentOfferProvider), isNull);
    },
  );

  testWidgets('detour offer auto-dismisses on its shorter 20s window', (
    tester,
  ) async {
    final container = _container();
    container.read(currentOfferProvider.notifier).state = _detourOffer;

    await tester.pumpWidget(_subject(container, _detourOffer));
    expect(find.text('20'), findsOneWidget);

    // Still live at a point where a fresh offer would also still be live —
    // proving the window really is per-offer data, not a shared constant.
    await tester.pump(const Duration(seconds: 15));
    expect(container.read(currentOfferProvider), isNotNull);

    await tester.pump(const Duration(seconds: 6));
    expect(container.read(currentOfferProvider), isNull);
  });

  testWidgets('countdown shifts to an urgent visual state as time runs out', (
    tester,
  ) async {
    final container = _container();
    container.read(currentOfferProvider.notifier).state = _freshOffer;
    await tester.pumpWidget(_subject(container, _freshOffer));

    Color secondsColor() => tester
        .widget<Text>(find.byKey(const ValueKey('countdown-seconds')))
        .style!
        .color!;

    // Calm at the start.
    expect(secondsColor(), AppColors.gold);

    // Past halfway: warning.
    await tester.pump(const Duration(seconds: 20));
    expect(find.text('15'), findsOneWidget);
    expect(secondsColor(), AppColors.warning);

    // Final quarter: unmistakably urgent.
    await tester.pump(const Duration(seconds: 28));
    expect(secondsColor(), AppColors.danger);
  });

  testWidgets(
    'detour offer is visually distinguishable from a fresh offer',
    (tester) async {
      final container = _container();

      await tester.pumpWidget(_subject(container, _freshOffer));
      expect(find.text('New delivery'), findsOneWidget);
      expect(find.text('New job'), findsOneWidget);
      expect(find.text('Accept'), findsOneWidget);
      expect(find.byKey(const ValueKey('offer-title-fresh')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('offer-distance-metric')),
        findsOneWidget,
      );
      // A fresh offer never frames itself as a route change.
      expect(find.text('Add a stop?'), findsNothing);
      expect(find.byKey(const ValueKey('offer-detour-metric')), findsNothing);

      final freshAccent = tester
          .widget<Text>(find.byKey(const ValueKey('offer-title-fresh')))
          .style!
          .color;

      final detourContainer = _container();
      await tester.pumpWidget(_subject(detourContainer, _detourOffer));
      await tester.pump();

      // Different header wording, different call to action, different metric.
      expect(find.text('Add a stop?'), findsOneWidget);
      expect(find.text('Route change'), findsOneWidget);
      expect(find.text('Add this stop'), findsOneWidget);
      expect(find.byKey(const ValueKey('offer-title-batch')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('offer-detour-metric')),
        findsOneWidget,
      );
      expect(find.text('+800 m detour'), findsOneWidget);
      expect(find.text('New delivery'), findsNothing);
      expect(find.byKey(const ValueKey('offer-title-fresh')), findsNothing);

      // And a different accent, so a glance mid-route is enough to tell them
      // apart without reading a word.
      final ring = tester.widget<Text>(
        find.byKey(const ValueKey('countdown-seconds')),
      );
      expect(ring.style!.color, AppColors.gold);
      expect(freshAccent, AppColors.paper);
    },
  );

  test('urgency escalates gold -> warning -> danger', () {
    expect(urgencyColor(1), AppColors.gold);
    expect(urgencyColor(0.6), AppColors.gold);
    expect(urgencyColor(0.4), AppColors.warning);
    expect(urgencyColor(0.26), AppColors.warning);
    expect(urgencyColor(0.25), AppColors.danger);
    expect(urgencyColor(0), AppColors.danger);

    expect(isUrgent(0.5), isFalse);
    expect(isUrgent(0.2), isTrue);
  });

  test('offer parses its window and kind from an alert payload', () {
    final detour = RiderOffer.fromAlert(
      const AlertMessage(
        kind: 'offer_batch_detour',
        delivery: AlertDelivery.foreground,
        data: {
          'assignment_id': 'a9',
          'order_id': 'o9',
          'offer_type': 'batch_detour',
          'shop_name': 'Fresh Mart',
          'window_seconds': '20',
          'delivery_fee_paise': '3000',
          'detour_meters': '640',
        },
      ),
    );

    expect(detour.kind, OfferKind.batchDetour);
    expect(detour.isBatchDetour, isTrue);
    expect(detour.windowSeconds, 20);
    expect(detour.detourMeters, 640);
    expect(detour.earningPaise, 3000);

    // A payload with no offer_type is a plain fresh offer on the 35s window.
    final fresh = RiderOffer.fromAlert(
      const AlertMessage(
        kind: 'offer_fresh',
        delivery: AlertDelivery.foreground,
        data: {'assignment_id': 'a8', 'order_id': 'o8'},
      ),
    );
    expect(fresh.kind, OfferKind.fresh);
    expect(fresh.windowSeconds, 35);
  });
}
