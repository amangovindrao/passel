import 'package:core/core.dart';
import 'package:delivery_app/src/alerts/alert_dispatcher.dart';
import 'package:delivery_app/src/providers/rider_models.dart';
import 'package:delivery_app/src/providers/rider_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

AlertMessage _alert(
  String kind,
  Map<String, String> data, {
  AlertDelivery delivery = AlertDelivery.foreground,
}) => AlertMessage(kind: kind, delivery: delivery, data: data);

ProviderContainer _container() {
  final container = ProviderContainer(
    overrides: [
      alertCenterProvider.overrideWith(
        (ref) => AlertCenter(transport: InMemoryAlertTransport()),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('a fresh offer alert becomes the current offer', () {
    final container = _container();

    container.read(alertDispatcherProvider).handle(
      _alert(RiderAlertKind.offerFresh, const {
        'assignment_id': 'a1',
        'order_id': 'o1',
        'shop_name': 'Corner Store',
        'delivery_fee_paise': '4500',
        'item_count': '3',
        'distance_to_shop_m': '850',
      }),
    );

    final offer = container.read(currentOfferProvider);
    expect(offer, isNotNull);
    expect(offer!.kind, OfferKind.fresh);
    expect(offer.shopName, 'Corner Store');
    expect(offer.windowSeconds, 35);
    expect(offer.earningPaise, 4500);
  });

  test('a detour alert becomes an offer on the shorter window', () {
    final container = _container();

    container.read(alertDispatcherProvider).handle(
      _alert(RiderAlertKind.offerBatchDetour, const {
        'assignment_id': 'a2',
        'order_id': 'o2',
        'offer_type': 'batch_detour',
        'shop_name': 'Fresh Mart',
        'window_seconds': '20',
        'detour_meters': '800',
        'delivery_fee_paise': '3000',
      }),
    );

    final offer = container.read(currentOfferProvider);
    expect(offer!.isBatchDetour, isTrue);
    expect(offer.windowSeconds, 20);
    expect(offer.detourMeters, 800);
  });

  test(
    'a Tier 1 add bumps the stop count and posts a notice, no offer surface',
    () {
      final container = _container();
      container.read(activeAssignmentProvider.notifier).state =
          const ActiveAssignment(
            assignmentId: 'a1',
            orderId: 'o1',
            shopName: 'Corner Store',
            orderStatus: 'PARTNER_ASSIGNED',
          );

      container.read(alertDispatcherProvider).handle(
        _alert(RiderAlertKind.batchAdded, const {
          'order_id': 'o5',
          'orders_on_trip': '2',
        }),
      );

      expect(container.read(activeAssignmentProvider)!.ordersOnTrip, 2);
      expect(
        container.read(batchAddedNoticeProvider),
        'Order #2 added to your pickup here',
      );
      // Consent-free by design: nothing to accept, so no offer surface.
      expect(container.read(currentOfferProvider), isNull);
    },
  );

  test('an order status alert advances the active assignment', () {
    final container = _container();
    container.read(activeAssignmentProvider.notifier).state =
        const ActiveAssignment(
          assignmentId: 'a1',
          orderId: 'o1',
          shopName: 'Corner Store',
          orderStatus: 'PARTNER_ASSIGNED',
        );

    container.read(alertDispatcherProvider).handle(
      _alert(RiderAlertKind.orderStatus, const {
        'order_id': 'o1',
        'status': 'PICKED_UP',
      }),
    );

    final assignment = container.read(activeAssignmentProvider)!;
    expect(assignment.orderStatus, 'PICKED_UP');
    expect(assignment.isBeforePickup, isFalse);
    expect(assignment.progressLabel, 'Picked up, heading to drop-off');
  });

  test('a finished order clears the active assignment', () {
    final container = _container();
    container.read(activeAssignmentProvider.notifier).state =
        const ActiveAssignment(
          assignmentId: 'a1',
          orderId: 'o1',
          shopName: 'Corner Store',
          orderStatus: 'OUT_FOR_DELIVERY',
        );

    container.read(alertDispatcherProvider).handle(
      _alert(RiderAlertKind.orderStatus, const {
        'order_id': 'o1',
        'status': 'DELIVERED',
      }),
    );

    // Cleared, so the dashboard drops the locked card and offers the toggle
    // back — going offline is allowed again the moment the job is done.
    expect(container.read(activeAssignmentProvider), isNull);
  });

  test('a status alert for a different order is ignored', () {
    final container = _container();
    container.read(activeAssignmentProvider.notifier).state =
        const ActiveAssignment(
          assignmentId: 'a1',
          orderId: 'o1',
          shopName: 'Corner Store',
          orderStatus: 'PARTNER_ASSIGNED',
        );

    container.read(alertDispatcherProvider).handle(
      _alert(RiderAlertKind.orderStatus, const {
        'order_id': 'someone-else',
        'status': 'DELIVERED',
      }),
    );

    expect(container.read(activeAssignmentProvider)!.orderStatus,
        'PARTNER_ASSIGNED');
  });

  test('an unrecognised alert kind changes nothing', () {
    final container = _container();

    container
        .read(alertDispatcherProvider)
        .handle(_alert('something_new', const {}));

    expect(container.read(currentOfferProvider), isNull);
    expect(container.read(activeAssignmentProvider), isNull);
    expect(container.read(batchAddedNoticeProvider), isNull);
  });
}
