import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_app/src/features/orders/order_detail_screen.dart';
import 'package:shop_app/src/providers/shop_providers.dart';
import 'package:ui_kit/ui_kit.dart';

import '../support/stubs.dart';

/// The shop's action flow for one order.
///
/// The load-bearing case is the packing photo: the state machine refuses
/// PREPARING -> READY_FOR_PICKUP without one, so a "Ready for pickup" button
/// that looks live before a photo exists is a button that always fails.
void main() {
  const shopId = 'shop-1';
  const orderId = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeee1234';
  const detailPath = '/orders/$orderId';

  Map<String, dynamic> detail({
    String status = 'PLACED',
    bool hasPackingPhoto = false,
    bool canAccept = true,
    bool canMarkReady = false,
    bool awaitingPayment = false,
    String paymentMode = 'cod',
    String? pickupCode,
    List<Map<String, dynamic>>? items,
  }) => {
    'id': orderId,
    'status': status,
    'item_count': 2,
    'item_total_paise': 15500,
    'delivery_fee_paise': 3000,
    'total_paise': 18500,
    'payment_mode': paymentMode,
    'payment_status': paymentMode == 'cod' ? 'not_required' : 'pending',
    'awaiting_payment': awaitingPayment,
    'placed_at': '2026-08-30T10:00:00+00:00',
    'items':
        items ??
        [
          {
            'id': 'line-1',
            'product_id': 'p1',
            'name': 'Toned Milk 500ml',
            'unit': 'pack',
            'qty': 2,
            'price_paise': 2700,
            'line_total_paise': 5400,
            'availability_status': 'available',
            'unavailable_reason': null,
          },
        ],
    'available_item_total_paise': 15500,
    'has_packing_photo': hasPackingPhoto,
    'can_accept': canAccept,
    'can_mark_ready': canMarkReady,
    'pickup_code': pickupCode,
  };

  late StubPackingPhotoUploader uploader;

  ({ProviderContainer container, StubHttpAdapter adapter}) build(
    Map<String, StubResponse> responses,
  ) {
    final api = stubApi(responses);
    final c = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(api.client),
        packingPhotoUploaderProvider.overrideWithValue(uploader),
      ],
    );
    addTearDown(c.dispose);
    return (container: c, adapter: api.adapter);
  }

  Widget subject(ProviderContainer c) => UncontrolledProviderScope(
    container: c,
    child: MaterialApp(
      theme: AppTheme.dark(),
      home: const ShopOrderDetailScreen(shopId: shopId, orderId: orderId),
    ),
  );

  void useTallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  setUp(() => uploader = StubPackingPhotoUploader());

  // --- Accepting and rejecting ---

  testWidgets('a new order offers accept and reject', (tester) async {
    useTallSurface(tester);
    final s = build({detailPath: StubResponse(200, detail())});

    await tester.pumpWidget(subject(s.container));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('accept-order')), findsOneWidget);
    expect(find.byKey(const ValueKey('reject-order')), findsOneWidget);
    expect(find.text('Toned Milk 500ml'), findsOneWidget);
  });

  testWidgets('accepting calls the accept endpoint', (tester) async {
    useTallSurface(tester);
    final s = build({
      detailPath: StubResponse(200, detail()),
      '$detailPath/accept': const StubResponse(200, {'status': 'PREPARING'}),
    });

    await tester.pumpWidget(subject(s.container));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('accept-order')));
    await tester.pumpAndSettle();

    expect(s.adapter.requestedPaths.any((p) => p.endsWith('/accept')), isTrue);
  });

  testWidgets('a refused accept surfaces the server message', (tester) async {
    useTallSurface(tester);
    final s = build({
      detailPath: StubResponse(200, detail()),
      '$detailPath/accept': StubResponse.error(
        422,
        'guard_failed',
        'Online order must be paid before shop can accept',
      ),
    });

    await tester.pumpWidget(subject(s.container));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('accept-order')));
    await tester.pumpAndSettle();

    // The existing shop screens throw the Result away and silently re-render.
    // This one has to say what happened.
    expect(
      find.text('Online order must be paid before shop can accept'),
      findsOneWidget,
    );
  });

  testWidgets('an unpaid online order explains itself instead of an accept '
      'button', (tester) async {
    useTallSurface(tester);
    final s = build({
      detailPath: StubResponse(
        200,
        detail(paymentMode: 'online', awaitingPayment: true, canAccept: false),
      ),
    });

    await tester.pumpWidget(subject(s.container));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('accept-order')), findsNothing);
    expect(find.textContaining('payment has not arrived'), findsOneWidget);
  });

  testWidgets('rejecting asks for confirmation first', (tester) async {
    useTallSurface(tester);
    final s = build({
      detailPath: StubResponse(200, detail()),
      '$detailPath/reject': const StubResponse(200, {
        'status': 'REJECTED_BY_SHOP',
      }),
    });

    await tester.pumpWidget(subject(s.container));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('reject-order')));
    await tester.pumpAndSettle();

    // Irreversible and visible to the customer immediately, so a stray tap must
    // not be enough.
    expect(find.text('Reject this order?'), findsOneWidget);
    expect(s.adapter.requestedPaths.any((p) => p.endsWith('/reject')), isFalse);

    await tester.tap(find.byKey(const ValueKey('confirm-reject')));
    await tester.pumpAndSettle();

    expect(s.adapter.requestedPaths.any((p) => p.endsWith('/reject')), isTrue);
  });

  // --- The packing photo gate ---

  testWidgets('ready for pickup is disabled until a photo exists', (
    tester,
  ) async {
    useTallSurface(tester);
    final s = build({
      detailPath: StubResponse(
        200,
        detail(status: 'PREPARING', canAccept: false),
      ),
    });

    await tester.pumpWidget(subject(s.container));
    await tester.pumpAndSettle();

    final button = tester.widget<PrimaryButton>(
      find.byKey(const ValueKey('mark-ready')),
    );
    expect(button.onPressed, isNull);
    expect(
      find.text('Add a photo of the packed bag to hand this over.'),
      findsOneWidget,
    );
  });

  testWidgets('ready for pickup becomes available once a photo is attached', (
    tester,
  ) async {
    useTallSurface(tester);
    final s = build({
      detailPath: StubResponse(
        200,
        detail(
          status: 'PREPARING',
          canAccept: false,
          hasPackingPhoto: true,
          canMarkReady: true,
        ),
      ),
    });

    await tester.pumpWidget(subject(s.container));
    await tester.pumpAndSettle();

    final button = tester.widget<PrimaryButton>(
      find.byKey(const ValueKey('mark-ready')),
    );
    expect(button.onPressed, isNotNull);
    expect(find.text('Packing photo added'), findsOneWidget);
  });

  testWidgets('tapping the photo tile uploads and posts the url', (
    tester,
  ) async {
    useTallSurface(tester);
    final s = build({
      detailPath: StubResponse(
        200,
        detail(status: 'PREPARING', canAccept: false),
      ),
      '$detailPath/packing-photo': const StubResponse(200, {
        'status': 'uploaded',
      }),
    });

    await tester.pumpWidget(subject(s.container));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('packing-photo-tile')));
    await tester.pumpAndSettle();

    expect(uploader.calls, 1);
    expect(
      s.adapter.requestedPaths.any((p) => p.endsWith('/packing-photo')),
      isTrue,
    );
  });

  testWidgets('backing out of the camera is not treated as a failure', (
    tester,
  ) async {
    useTallSurface(tester);
    uploader.url = null; // The shopkeeper cancelled.
    final s = build({
      detailPath: StubResponse(
        200,
        detail(status: 'PREPARING', canAccept: false),
      ),
    });

    await tester.pumpWidget(subject(s.container));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('packing-photo-tile')));
    await tester.pumpAndSettle();

    expect(uploader.calls, 1);
    // Nothing posted, and no error shown for someone who changed their mind.
    expect(
      s.adapter.requestedPaths.any((p) => p.endsWith('/packing-photo')),
      isFalse,
    );
    expect(find.byType(AppSnackbar), findsNothing);
  });

  testWidgets('a failed upload says why', (tester) async {
    useTallSurface(tester);
    uploader.failWith = 'Could not upload that photo.';
    final s = build({
      detailPath: StubResponse(
        200,
        detail(status: 'PREPARING', canAccept: false),
      ),
    });

    await tester.pumpWidget(subject(s.container));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('packing-photo-tile')));
    await tester.pumpAndSettle();

    expect(find.text('Could not upload that photo.'), findsOneWidget);
  });

  testWidgets('marking ready reports whether a rider was found', (
    tester,
  ) async {
    useTallSurface(tester);
    final s = build({
      detailPath: StubResponse(
        200,
        detail(
          status: 'PREPARING',
          canAccept: false,
          hasPackingPhoto: true,
          canMarkReady: true,
        ),
      ),
      '$detailPath/mark-ready': const StubResponse(200, {
        'status': 'READY_FOR_PICKUP',
        'assignment_id': null,
      }),
    });

    await tester.pumpWidget(subject(s.container));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mark-ready')));
    await tester.pumpAndSettle();

    // No rider yet is a normal outcome, not a failure — say so plainly.
    expect(find.text('Marked ready. Looking for a rider.'), findsOneWidget);
  });

  // --- Unavailable items ---

  testWidgets('an unavailable line is struck through with its reason', (
    tester,
  ) async {
    useTallSurface(tester);
    final s = build({
      detailPath: StubResponse(
        200,
        detail(
          status: 'PREPARING',
          canAccept: false,
          items: [
            {
              'id': 'line-1',
              'product_id': 'p1',
              'name': 'Farm Eggs (6)',
              'unit': 'tray',
              'qty': 1,
              'price_paise': 6600,
              'line_total_paise': 6600,
              'availability_status': 'unavailable',
              'unavailable_reason': 'Sold out this morning',
            },
          ],
        ),
      ),
    });

    await tester.pumpWidget(subject(s.container));
    await tester.pumpAndSettle();

    expect(find.text('Sold out this morning'), findsOneWidget);
    // Already unavailable, so there is nothing left to mark.
    expect(find.byKey(const ValueKey('mark-unavailable-line-1')), findsNothing);
  });

  testWidgets('marking an item unavailable asks for a reason and sends it', (
    tester,
  ) async {
    useTallSurface(tester);
    final s = build({
      detailPath: StubResponse(
        200,
        detail(status: 'PREPARING', canAccept: false),
      ),
      '/items/line-1/mark-unavailable': const StubResponse(200, {
        'status': 'AWAITING_CUSTOMER_DECISION',
      }),
    });

    await tester.pumpWidget(subject(s.container));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mark-unavailable-line-1')));
    await tester.pumpAndSettle();

    expect(find.text('Toned Milk 500ml unavailable'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('confirm-unavailable')));
    await tester.pumpAndSettle();

    expect(
      s.adapter.requestedPaths.any((p) => p.endsWith('/mark-unavailable')),
      isTrue,
    );
  });

  testWidgets('an item cannot be marked unavailable once it has left the '
      'shop', (tester) async {
    useTallSurface(tester);
    final s = build({
      detailPath: StubResponse(
        200,
        detail(status: 'PARTNER_ASSIGNED', canAccept: false),
      ),
    });

    await tester.pumpWidget(subject(s.container));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('mark-unavailable-line-1')), findsNothing);
  });

  // --- The pickup code ---

  testWidgets('the pickup code shows only once a rider is coming', (
    tester,
  ) async {
    useTallSurface(tester);
    final s = build({
      detailPath: StubResponse(
        200,
        detail(
          status: 'PARTNER_ASSIGNED',
          canAccept: false,
          hasPackingPhoto: true,
          pickupCode: '8241',
        ),
      ),
    });

    await tester.pumpWidget(subject(s.container));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('pickup-code')), findsOneWidget);
    expect(find.text('8241'), findsOneWidget);
  });

  testWidgets('no pickup code is shown while still packing', (tester) async {
    useTallSurface(tester);
    final s = build({
      detailPath: StubResponse(
        200,
        detail(status: 'PREPARING', canAccept: false),
      ),
    });

    await tester.pumpWidget(subject(s.container));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('pickup-code')), findsNothing);
  });
}
