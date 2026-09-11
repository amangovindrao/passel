import 'package:core/core.dart';
import 'package:customer_app/src/providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Payment method selection.
final paymentMethodProvider = StateProvider<String>((ref) => 'online');

/// Quote result from the backend.
class QuoteResult {
  const QuoteResult({
    required this.distanceKm,
    required this.deliveryFeePaise,
    required this.deliveryRatePerKm,
    required this.minOrderPaise,
  });

  factory QuoteResult.fromJson(Map<String, dynamic> json) => QuoteResult(
    distanceKm: (json['distance_km'] as num).toDouble(),
    deliveryFeePaise: json['delivery_fee_paise'] as int,
    deliveryRatePerKm: json['delivery_rate_per_km'] as int,
    minOrderPaise: json['min_order_paise'] as int,
  );

  final double distanceKm;
  final int deliveryFeePaise;
  final int deliveryRatePerKm;
  final int minOrderPaise;
}

/// Quote provider — re-fetches when active address changes.
final quoteProvider = FutureProvider.autoDispose<QuoteResult?>((ref) async {
  final address = ref.watch(activeAddressProvider);
  final cart = ref.watch(cartProvider);
  if (address == null || cart.shopId == null) return null;

  final client = ref.watch(apiClientProvider);
  final result = await client.post<Map<String, dynamic>>(
    '/api/v1/orders/quote',
    data: {'shop_id': cart.shopId, 'address_id': address.id},
    fromJson: (data) => data as Map<String, dynamic>,
  );
  return result.when(
    success: QuoteResult.fromJson,
    failure: (AppError _) => null,
  );
});

/// Order placement result.
class PlacementResult {
  const PlacementResult({
    required this.orderId,
    required this.paymentMode,
    required this.paymentStatus,
    this.razorpayOrderId,
    this.razorpayKey,
  });

  final String orderId;
  final String? razorpayOrderId;
  final String? razorpayKey;
  final String paymentMode;
  final String paymentStatus;
}

/// Order placement — creates order, handles payment flow.
final orderPlacementProvider = FutureProvider.autoDispose
    .family<PlacementResult?, String?>((ref, notes) async {
      final cart = ref.read(cartProvider);
      final address = ref.read(activeAddressProvider);
      final paymentMode = ref.read(paymentMethodProvider);
      if (cart.isEmpty || cart.shopId == null || address == null) {
        return null;
      }

      final client = ref.read(apiClientProvider);

      // Generate idempotency key (UUID)
      final idempotencyKey = _generateUuid();

      final items = cart.items.values
          .map((i) => {'product_id': i.product.id, 'qty': i.quantity})
          .toList();

      final result = await client.post<Map<String, dynamic>>(
        '/api/v1/orders',
        data: {
          'shop_id': cart.shopId,
          'address_id': address.id,
          'items': items,
          'payment_mode': paymentMode,
          'notes': notes,
          'idempotency_key': idempotencyKey,
        },
        fromJson: (data) => data as Map<String, dynamic>,
      );

      return result.when(
        success: (Map<String, dynamic> data) {
          // Clear cart on success
          ref.read(cartProvider.notifier).clearCart();
          return PlacementResult(
            orderId: data['order_id'] as String,
            razorpayOrderId: data['razorpay_order_id'] as String?,
            razorpayKey: data['razorpay_key_id'] as String?,
            paymentMode: data['payment_mode'] as String,
            paymentStatus: data['payment_status'] as String,
          );
        },
        failure: (AppError error) => throw error,
      );
    });

String _generateUuid() {
  // Simple UUID v4 generation without external dependency
  final now = DateTime.now().microsecondsSinceEpoch;
  return '${_hex(now)}-${_hex(now >> 16)}-4${_hex(now >> 32).substring(1)}'
          '-${_hex(now >> 48)}-${_hex(now)}'
      .replaceAll(RegExp('[^0-9a-f-]'), '0')
      .substring(0, 36);
}

String _hex(int value) =>
    (value.abs() % 0xFFFF).toRadixString(16).padLeft(4, '0');
