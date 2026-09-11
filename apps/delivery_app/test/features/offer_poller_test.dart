import 'package:delivery_app/src/providers/rider_models.dart';
import 'package:delivery_app/src/services/offer_poller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/stubs.dart';

/// The pull route for offers. On a build with no working push channel this is
/// the *only* way a rider ever learns an offer exists, so the cases that
/// matter are the ones where it must not lie: a countdown it did not compute
/// itself, an offer already answered, and a server that has not caught up yet.
void main() {
  Map<String, dynamic> anOffer({
    String assignmentId = 'a1',
    String offerType = 'fresh',
    int windowSeconds = 35,
    int? detourMeters,
    int? distanceToShopM = 480,
  }) => {
    'assignment_id': assignmentId,
    'order_id': 'o1',
    'offer_type': offerType,
    'shop_name': 'Corner Store',
    'item_count': 5,
    'delivery_fee_paise': 3000,
    'distance_to_shop_m': distanceToShopM,
    'detour_meters': detourMeters,
    'window_seconds': windowSeconds,
  };

  /// A poller over a response the test can rewrite between polls, plus the
  /// offer state it reads and writes.
  ///
  /// `serve` swaps what the next poll finds, which is what makes the
  /// withdrawn-offer and already-answered cases testable on one poller rather
  /// than two unrelated ones.
  ({
    OfferPoller poller,
    List<RiderOffer?> writes,
    RiderOffer? Function() read,
    void Function(RiderOffer?) set,
    void Function(Map<String, dynamic>?) serve,
  })
  build({Map<String, dynamic>? offer, int statusCode = 200}) {
    RiderOffer? current;
    final writes = <RiderOffer?>[];
    final body = <String, dynamic>{'offer': offer};

    final poller = OfferPoller(
      client: stubApiClient({OfferPoller.path: StubResponse(statusCode, body)}),
      readOffer: () => current,
      writeOffer: (value) {
        current = value;
        writes.add(value);
      },
    );

    return (
      poller: poller,
      writes: writes,
      read: () => current,
      set: (value) => current = value,
      serve: (value) => body['offer'] = value,
    );
  }

  test('a waiting offer is surfaced with everything the card needs', () async {
    final s = build(offer: anOffer());

    await s.poller.poll();

    final offer = s.read();
    expect(offer, isNotNull);
    expect(offer!.assignmentId, 'a1');
    expect(offer.orderId, 'o1');
    expect(offer.kind, OfferKind.fresh);
    expect(offer.shopName, 'Corner Store');
    expect(offer.itemCount, 5);
    expect(offer.earningPaise, 3000);
    expect(offer.distanceToShopMeters, 480);
  });

  test('no offer writes nothing at all', () async {
    final s = build();

    await s.poller.poll();

    expect(s.read(), isNull);
    // Not even a null: a redundant write would churn every listener four times
    // a minute for as long as the rider is online.
    expect(s.writes, isEmpty);
  });

  test('the countdown comes from the server, not the full window', () async {
    // Polled 30s into a 35s window.
    final s = build(offer: anOffer(windowSeconds: 5));

    await s.poller.poll();

    // Trusting the client's own idea of the window would show five seconds that
    // do not exist, then fail the accept at the end of them.
    expect(s.read()!.windowSeconds, 5);
  });

  test('a detour offer keeps its type, detour and shorter window', () async {
    final s = build(
      offer: anOffer(
        offerType: 'batch_detour',
        windowSeconds: 18,
        detourMeters: 640,
      ),
    );

    await s.poller.poll();

    final offer = s.read()!;
    expect(offer.kind, OfferKind.batchDetour);
    expect(offer.isBatchDetour, isTrue);
    expect(offer.detourMeters, 640);
    expect(offer.windowSeconds, 18);
  });

  test('a missing distance still yields an offer', () async {
    final s = build(offer: anOffer(distanceToShopM: null));

    await s.poller.poll();

    expect(s.read(), isNotNull);
    expect(s.read()!.distanceToShopMeters, isNull);
  });

  test('re-polling the same offer does not rewrite it', () async {
    final s = build(offer: anOffer());

    await s.poller.poll();
    await s.poller.poll();
    await s.poller.poll();

    // Rewriting would restart the countdown ring on every poll, and the window
    // would never close.
    expect(s.writes, hasLength(1));
  });

  test('an offer withdrawn server-side is taken off screen', () async {
    final s = build(offer: anOffer());
    await s.poller.poll();
    expect(s.read(), isNotNull);

    // Expired, or handed to someone closer.
    s.serve(null);
    await s.poller.poll();

    expect(s.read(), isNull);
    expect(s.writes, [isNotNull, isNull]);
  });

  test('a settled offer is never surfaced again', () async {
    final s = build(offer: anOffer());
    await s.poller.poll();

    // What accepting does: the card clears, and the poller is told why.
    s.poller.markSettled('a1');
    s.set(null);

    // The server still reports it as offered — the worker has not run yet.
    await s.poller.poll();

    expect(s.read(), isNull, reason: 'an answered offer must not come back');
  });

  test('a different offer still gets through after one is settled', () async {
    final s = build(offer: anOffer());
    await s.poller.poll();
    s.poller.markSettled('a1');
    s.set(null);

    s.serve(anOffer(assignmentId: 'a2'));
    await s.poller.poll();

    expect(s.read()?.assignmentId, 'a2');
  });

  test(
    'a reply already in the air when the rider answers is discarded',
    () async {
      final s = build(offer: anOffer());

      // Start the round trip, then settle before it lands.
      final inFlight = s.poller.poll();
      s.poller.markSettled('a1');
      await inFlight;

      expect(
        s.read(),
        isNull,
        reason: 'an accepted offer must not come back on screen',
      );
    },
  );

  test('overlapping polls collapse into one request', () async {
    final s = build(offer: anOffer());

    await Future.wait([s.poller.poll(), s.poller.poll(), s.poller.poll()]);

    expect(s.writes, hasLength(1));
  });

  test('a failed poll changes nothing and does not throw', () async {
    final s = build(statusCode: 500);
    s.serve(anOffer());

    await s.poller.poll();

    expect(s.read(), isNull);
    expect(s.writes, isEmpty);
  });

  test('start polls immediately rather than after a full interval', () async {
    final s = build(offer: anOffer());

    s.poller.start();
    addTearDown(s.poller.stop);
    // Drain the round trip rather than wait out the 4s interval — the point is
    // that start() does not make the rider wait for the first tick.
    await pumpEventQueue();

    expect(s.poller.isRunning, isTrue);
    expect(s.read(), isNotNull);
  });

  test('stop halts the loop', () async {
    final s = build(offer: anOffer());

    s.poller.start();
    expect(s.poller.isRunning, isTrue);

    s.poller.stop();

    expect(s.poller.isRunning, isFalse);
  });
}
