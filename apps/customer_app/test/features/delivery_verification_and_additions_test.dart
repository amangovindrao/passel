import 'package:core/core.dart';
import 'package:customer_app/src/features/tracking/live_tracking_screen.dart';
import 'package:customer_app/src/providers/order_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _MockOrderRepository extends Fake implements OrderRepository {
  bool verifyItemsCalled = false;
  String? verifyItemsOrderId;
  String? verifyItemsAction;

  @override
  Future<Result<Map<String, dynamic>>> verifyItems({
    required String orderId,
    required String action,
  }) async {
    verifyItemsCalled = true;
    verifyItemsOrderId = orderId;
    verifyItemsAction = action;
    return Result.success({
      'order_id': orderId,
      'status': 'DELIVERED',
      'verification_status': 'ALL_CORRECT',
      'message': 'Order verified and completed.',
    });
  }
}

void main() {
  const testOrderId = 'ord_test_verification_123';

  final pendingCheckTracking = TrackingData(
    orderId: testOrderId,
    status: 'HANDOVER_READY',
    statusHistory: [
      StatusHistoryEntry(status: 'PLACED', createdAt: DateTime.now().subtract(const Duration(minutes: 15)).toIso8601String()),
      StatusHistoryEntry(status: 'OUT_FOR_DELIVERY', createdAt: DateTime.now().subtract(const Duration(minutes: 5)).toIso8601String()),
      StatusHistoryEntry(status: 'HANDOVER_READY', createdAt: DateTime.now().toIso8601String()),
    ],
    verificationStatus: 'PENDING_CHECK',
    remainingSeconds: 400,
    additionWindowStatus: 'OPEN',
    canAddMore: true,
  );

  const testOrderDetail = OrderDetail(
    id: testOrderId,
    shopId: 'shop_123',
    status: 'HANDOVER_READY',
    itemTotalPaise: 5000,
    deliveryFeePaise: 2500,
    paymentMode: 'online',
    items: [
      OrderDetailItem(
        id: 'item_1',
        qty: 1,
        pricePaise: 5000,
        availability: 'AVAILABLE',
      ),
    ],
    statusHistory: [],
    photos: [],
    ratings: [],
  );

  testWidgets('renders 7-minute verification card, countdown timer, and primary action', (tester) async {
    final mockRepo = _MockOrderRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trackingProvider(testOrderId).overrideWith((ref) => pendingCheckTracking),
          orderDetailProvider(testOrderId).overrideWith((ref) => testOrderDetail),
          orderRepositoryProvider.overrideWithValue(mockRepo),
        ],
        child: const MaterialApp(
          home: LiveTrackingScreen(orderId: testOrderId),
        ),
      ),
    );
    await tester.pump();

    // Verify Hero and Verification banner
    expect(find.text('Rider Arrived!'), findsOneWidget);
    expect(find.text('Check Your Items'), findsOneWidget);
    expect(find.text('06:40 left'), findsOneWidget);
    expect(find.text('Everything is correct'), findsOneWidget);
    expect(find.text('Something is wrong'), findsOneWidget);

    // Verify Add More Card
    expect(find.text('Add More to This Order'), findsOneWidget);
    expect(find.text('Add More Items'), findsOneWidget);

    // Tap Everything is correct
    await tester.tap(find.text('Everything is correct'));
    await tester.pump();

    expect(mockRepo.verifyItemsCalled, isTrue);
    expect(mockRepo.verifyItemsOrderId, testOrderId);
    expect(mockRepo.verifyItemsAction, 'everything_correct');
  });

  testWidgets('tapping Something is wrong opens issue sheet with Expired Item Safety Guarantee', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mockRepo = _MockOrderRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trackingProvider(testOrderId).overrideWith((ref) => pendingCheckTracking),
          orderDetailProvider(testOrderId).overrideWith((ref) => testOrderDetail),
          orderRepositoryProvider.overrideWithValue(mockRepo),
        ],
        child: const MaterialApp(
          home: LiveTrackingScreen(orderId: testOrderId),
        ),
      ),
    );
    await tester.pump();

    // Tap Something is wrong
    await tester.tap(find.text('Something is wrong'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Verify sheet contents
    expect(find.text('Report an Issue'), findsOneWidget);
    expect(find.text('Expired item'), findsOneWidget);
    expect(find.text('Missing item'), findsOneWidget);
    expect(find.text('Wrong item'), findsOneWidget);
    expect(find.text('Damaged item'), findsOneWidget);
    expect(find.text('Product Safety Guarantee: The shop bears all return costs. 100% instant refund.'), findsOneWidget);
  });

  testWidgets('tapping Add More Items opens bottom sheet for incremental items', (tester) async {
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final mockRepo = _MockOrderRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trackingProvider(testOrderId).overrideWith((ref) => pendingCheckTracking),
          orderDetailProvider(testOrderId).overrideWith((ref) => testOrderDetail),
          orderRepositoryProvider.overrideWithValue(mockRepo),
        ],
        child: const MaterialApp(
          home: LiveTrackingScreen(orderId: testOrderId),
        ),
      ),
    );
    await tester.pump();

    // Tap Add More Items
    await tester.tap(find.text('Add More Items'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Add More Items'), findsWidgets);
    expect(find.text('Amul Taaza Milk 500ml'), findsOneWidget);
    expect(find.text('Adding to your arriving delivery • No extra delivery fee'), findsOneWidget);
  });
}
