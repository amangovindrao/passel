import 'package:core/core.dart';
import 'package:customer_app/src/providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Payment method selection ('online', 'cod', 'wallet').
final paymentMethodProvider = StateProvider<String>((ref) => 'online');

/// Whether user opted to use wallet balance.
final useWalletProvider = StateProvider<bool>((ref) => false);

/// Quote result from the backend.
class QuoteResult {
  const QuoteResult({
    required this.distanceKm,
    required this.deliveryFeePaise,
    required this.deliveryRatePerKm,
    required this.minOrderPaise,
    this.walletBalancePaise = 0,
    this.bundleShopsCount = 1,
    this.anchorShopId,
  });

  factory QuoteResult.fromJson(Map<String, dynamic> json) => QuoteResult(
    distanceKm: (json['distance_km'] as num).toDouble(),
    deliveryFeePaise: json['delivery_fee_paise'] as int,
    deliveryRatePerKm: json['delivery_rate_per_km'] as int,
    minOrderPaise: json['min_order_paise'] as int,
    walletBalancePaise: json['wallet_balance_paise'] as int? ?? 0,
    bundleShopsCount: json['bundle_shops_count'] as int? ?? 1,
    anchorShopId: json['anchor_shop_id'] as String?,
  );

  final double distanceKm;
  final int deliveryFeePaise;
  final int deliveryRatePerKm;
  final int minOrderPaise;
  final int walletBalancePaise;
  final int bundleShopsCount;
  final String? anchorShopId;
}

/// Quote provider — re-fetches when active address or cart changes.
final quoteProvider = FutureProvider.autoDispose<QuoteResult?>((ref) async {
  final address = ref.watch(activeAddressProvider);
  final cart = ref.watch(cartProvider);
  if (address == null || cart.shopId == null) return null;

  final client = ref.watch(apiClientProvider);
  final shopIds = cart.allShopIds.toList();
  final result = await client.post<Map<String, dynamic>>(
    '/api/v1/orders/quote',
    data: {
      'shop_id': cart.shopId,
      'shop_ids': shopIds,
      'address_id': address.id,
    },
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
    this.walletAmountUsedPaise = 0,
    this.isMultiShop = false,
  });

  final String orderId;
  final String? razorpayOrderId;
  final String? razorpayKey;
  final String paymentMode;
  final String paymentStatus;
  final int walletAmountUsedPaise;
  final bool isMultiShop;
}

/// Order placement — creates order, handles payment flow.
final orderPlacementProvider = FutureProvider.autoDispose
    .family<PlacementResult?, String?>((ref, notes) async {
      final cart = ref.read(cartProvider);
      final address = ref.read(activeAddressProvider);
      final paymentMode = ref.read(paymentMethodProvider);
      final useWallet = ref.read(useWalletProvider);
      if (cart.isEmpty || cart.shopId == null || address == null) {
        return null;
      }

      final client = ref.read(apiClientProvider);

      // Generate idempotency key (UUID)
      final idempotencyKey = _generateUuid();

      final itemsByShop = cart.itemsByShop;
      final shopsPayload = itemsByShop.entries.map((entry) {
        return {
          'shop_id': entry.key,
          'items': entry.value
              .map((i) => {'product_id': i.product.id, 'qty': i.quantity})
              .toList(),
        };
      }).toList();

      final allItems = cart.items.values
          .map((i) => {'product_id': i.product.id, 'qty': i.quantity})
          .toList();

      final result = await client.post<Map<String, dynamic>>(
        '/api/v1/orders',
        data: {
          'shop_id': cart.shopId,
          'address_id': address.id,
          'items': allItems,
          'shops': shopsPayload,
          'payment_mode': paymentMode,
          'use_wallet': useWallet,
          'notes': notes,
          'idempotency_key': idempotencyKey,
        },
        fromJson: (data) => data as Map<String, dynamic>,
      );

      return result.when(
        success: (Map<String, dynamic> data) {
          // Clear cart on success and refresh wallet
          ref.read(cartProvider.notifier).clearCart();
          ref.invalidate(walletDataProvider);
          return PlacementResult(
            orderId: data['order_id'] as String,
            razorpayOrderId: data['razorpay_order_id'] as String?,
            razorpayKey: data['razorpay_key_id'] as String?,
            paymentMode: data['payment_mode'] as String,
            paymentStatus: data['payment_status'] as String,
            walletAmountUsedPaise:
                data['wallet_amount_used_paise'] as int? ?? 0,
            isMultiShop: data['is_multi_shop'] as bool? ?? false,
          );
        },
        failure: (AppError error) => throw error,
      );
    });

String _generateUuid() {
  final now = DateTime.now().microsecondsSinceEpoch;
  return '${_hex(now)}-${_hex(now >> 16)}-4${_hex(now >> 32).substring(1)}'
          '-${_hex(now >> 48)}-${_hex(now)}'
      .replaceAll(RegExp('[^0-9a-f-]'), '0')
      .substring(0, 36);
}

String _hex(int value) =>
    (value.abs() % 0xFFFF).toRadixString(16).padLeft(4, '0');
