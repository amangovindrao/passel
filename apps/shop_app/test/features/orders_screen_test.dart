import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_app/src/features/orders/orders_screen.dart';
import 'package:shop_app/src/providers/shop_providers.dart';
import 'package:ui_kit/ui_kit.dart';

import '../support/stubs.dart';

/// The shop's order queue. Before this screen existed a customer could place an
/// order and nobody at the shop had any way to find out, so the case that
/// matters most is simply that an order shows up and is legible at a glance.
void main() {
  const ordersPath = '/orders';

  Map<String, dynamic> order({
    String id = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeee1234',
    String status = 'PLACED',
    int itemCount = 3,
    int totalPaise = 18500,
    String paymentMode = 'cod',
    bool awaitingPayment = false,
  }) => {
    'id': id,
    'status': status,
    'item_count': itemCount,
    'item_total_paise': totalPaise - 3000,
    'delivery_fee_paise': 3000,
    'total_paise': totalPaise,
    'payment_mode': paymentMode,
    'payment_status': paymentMode == 'cod' ? 'not_required' : 'pending',
    'awaiting_payment': awaitingPayment,
    'placed_at': '2026-08-30T10:00:00+00:00',
  };

  ProviderContainer containerFor(StubResponse response) {
    final api = stubApi({ordersPath: response});
    final c = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(api.client)],
    );
    addTearDown(c.dispose);
    return c;
  }

  Widget subject(ProviderContainer c) => UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      theme: AppTheme.dark(),
      home: const OrdersScreen(shopId: 'shop-1'),
    ),
  );

  /// A tall surface: ListView does not build children that would be off-screen,
  /// and the default 800x600 test view hides the lower sections.
  void useTallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('an order appears with its status, item count and total', (
    tester,
  ) async {
    useTallSurface(tester);
    final c = containerFor(StubResponse(200, [order()]));

    await tester.pumpWidget(subject(c));
    await tester.pumpAndSettle();

    expect(find.text('#1234'), findsOneWidget);
    expect(find.text('3 items'), findsOneWidget);
    expect(find.text('Cash on delivery'), findsOneWidget);
    // 'New' rather than 'PLACED' — the badge speaks the shopkeeper's language.
    expect(find.text('New'), findsOneWidget);
  });

  testWidgets('one item is not pluralised', (tester) async {
    useTallSurface(tester);
    final c = containerFor(StubResponse(200, [order(itemCount: 1)]));

    await tester.pumpWidget(subject(c));
    await tester.pumpAndSettle();

    expect(find.text('1 item'), findsOneWidget);
  });

  testWidgets('new orders are separated from ones already in progress', (
    tester,
  ) async {
    useTallSurface(tester);
    final c = containerFor(
      StubResponse(200, [
        order(id: 'new-order-0001'),
        order(id: 'busy-order-0002', status: 'PREPARING'),
      ]),
    );

    await tester.pumpWidget(subject(c));
    await tester.pumpAndSettle();

    // The split is the point: a shop scanning this screen needs to see what it
    // has not looked at yet, not a flat date-ordered list.
    expect(find.text('Needs your attention'), findsOneWidget);
    expect(find.text('In progress'), findsOneWidget);
  });

  testWidgets('no section header appears when nothing is new', (tester) async {
    useTallSurface(tester);
    final c = containerFor(
      StubResponse(200, [order(status: 'PREPARING')]),
    );

    await tester.pumpWidget(subject(c));
    await tester.pumpAndSettle();

    expect(find.text('Needs your attention'), findsNothing);
    expect(find.text('In progress'), findsOneWidget);
  });

  testWidgets('an unpaid online order says so instead of looking actionable', (
    tester,
  ) async {
    useTallSurface(tester);
    final c = containerFor(
      StubResponse(200, [
        order(paymentMode: 'online', awaitingPayment: true),
      ]),
    );

    await tester.pumpWidget(subject(c));
    await tester.pumpAndSettle();

    expect(find.text('Waiting for payment'), findsOneWidget);
  });

  testWidgets('an empty queue explains itself rather than showing blank', (
    tester,
  ) async {
    final c = containerFor(const StubResponse(200, <Object>[]));

    await tester.pumpWidget(subject(c));
    await tester.pumpAndSettle();

    expect(find.text('No orders right now'), findsOneWidget);
    expect(find.byType(EmptyStateView), findsOneWidget);
  });

  testWidgets('a failure offers a retry, not a raw exception', (tester) async {
    final c = containerFor(
      StubResponse.error(500, 'server_error', 'Database is having a moment'),
    );

    await tester.pumpWidget(subject(c));
    await tester.pumpAndSettle();

    // This is the screen a shop sits on all day; a dead end is not acceptable.
    expect(find.text("Couldn't load your orders"), findsOneWidget);
    expect(find.text('Database is having a moment'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
}
