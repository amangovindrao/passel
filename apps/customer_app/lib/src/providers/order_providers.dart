import 'package:core/core.dart';
import 'package:customer_app/src/providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Order repository provider.
final orderRepositoryProvider = Provider<OrderRepository>(
  (ref) => OrderRepository(ref.watch(apiClientProvider)),
);

/// Active orders.
final activeOrdersProvider = FutureProvider.autoDispose<List<OrderSummary>>((
  ref,
) async {
  final repo = ref.watch(orderRepositoryProvider);
  final result = await repo.listOrders(status: 'active');
  return result.when(
    success: (List<OrderSummary> orders) => orders,
    failure: (AppError e) => throw e,
  );
});

/// Past orders.
final pastOrdersProvider = FutureProvider.autoDispose<List<OrderSummary>>((
  ref,
) async {
  final repo = ref.watch(orderRepositoryProvider);
  final result = await repo.listOrders(status: 'completed');
  return result.when(
    success: (List<OrderSummary> orders) => orders,
    failure: (AppError e) => throw e,
  );
});

/// Order detail.
final orderDetailProvider = FutureProvider.autoDispose
    .family<OrderDetail, String>((ref, orderId) async {
      final repo = ref.watch(orderRepositoryProvider);
      final result = await repo.getDetail(orderId);
      return result.when(
        success: (OrderDetail detail) => detail,
        failure: (AppError e) => throw e,
      );
    });

/// Live tracking data (polls + realtime in production).
final trackingProvider = FutureProvider.autoDispose
    .family<TrackingData, String>((ref, orderId) async {
      final repo = ref.watch(orderRepositoryProvider);
      final result = await repo.getTracking(orderId);
      return result.when(
        success: (TrackingData data) => data,
        failure: (AppError e) => throw e,
      );
    });

/// Missing item interstitial state.
class MissingItemPayload {
  const MissingItemPayload({
    required this.orderId,
    required this.itemName,
    required this.reason,
    required this.originalTotalPaise,
    required this.revisedTotalPaise,
    required this.timeoutSeconds,
  });

  final String orderId;
  final String itemName;
  final String reason;
  final int originalTotalPaise;
  final int revisedTotalPaise;
  final int timeoutSeconds;
}

/// Root-level provider that FCM data messages push to.
final missingItemInterstitialProvider = StateProvider<MissingItemPayload?>(
  (ref) => null,
);
