import 'package:core/core.dart';
import 'package:delivery_app/main.dart';
import 'package:delivery_app/src/features/offers/offer_screen.dart';
import 'package:delivery_app/src/providers/rider_models.dart';
import 'package:delivery_app/src/providers/rider_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

const _offer = RiderOffer(
  assignmentId: 'a1',
  orderId: 'o1',
  kind: OfferKind.fresh,
  shopName: 'Corner Store',
  windowSeconds: 35,
  earningPaise: 4500,
);

void main() {
  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [
        alertCenterProvider.overrideWith(
          (ref) => AlertCenter(transport: InMemoryAlertTransport()),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  Widget subject(ProviderContainer c) => UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      theme: AppTheme.dark(),
      home: const OfferHost(
        child: Scaffold(body: Center(child: Text('dashboard behind'))),
      ),
    ),
  );

  testWidgets('no offer means the host is invisible', (tester) async {
    final c = container();

    await tester.pumpWidget(subject(c));

    expect(find.text('dashboard behind'), findsOneWidget);
    expect(find.byType(OfferScreen), findsNothing);
  });

  testWidgets('an offer overlays whatever screen the rider is on', (
    tester,
  ) async {
    final c = container();
    await tester.pumpWidget(subject(c));

    c.read(currentOfferProvider.notifier).state = _offer;
    await tester.pump();

    expect(find.byType(OfferScreen), findsOneWidget);
    expect(find.text('New delivery'), findsOneWidget);

    // Overlaid, not pushed: the screen underneath is untouched and there is no
    // navigation stack to unwind when the offer resolves.
    expect(find.text('dashboard behind'), findsOneWidget);
  });

  testWidgets('clearing the offer restores the screen underneath', (
    tester,
  ) async {
    final c = container();
    await tester.pumpWidget(subject(c));

    c.read(currentOfferProvider.notifier).state = _offer;
    await tester.pump();
    expect(find.byType(OfferScreen), findsOneWidget);

    c.read(currentOfferProvider.notifier).state = null;
    await tester.pump();

    expect(find.byType(OfferScreen), findsNothing);
    expect(find.text('dashboard behind'), findsOneWidget);
  });
}
