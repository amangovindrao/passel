import 'package:core/core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shop_app/src/services/packing_photo_uploader.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ui_kit/ui_kit.dart';

// --- API ---
final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

final supabaseProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

/// Packing photo capture and storage. A provider so tests can override it and
/// never touch the camera or a storage bucket.
final packingPhotoUploaderProvider = Provider<PackingPhotoUploader>(
  (ref) => PackingPhotoUploader(),
);

/// Phone OTP send and verify. Behind a provider so onboarding can be tested
/// without a live Supabase instance.
final phoneAuthProvider = Provider<PhoneAuth>((ref) => PhoneAuth());

// --- Shop Data ---

class ShopData {
  const ShopData({
    required this.exists,
    this.shopId,
    this.name,
    this.category,
    this.isOpen,
    this.subscriptionStatus,
    this.kycStatus,
    this.trialEndDate,
  });

  factory ShopData.fromJson(Map<String, dynamic> json) => ShopData(
    exists: json['exists'] as bool,
    shopId: json['shop_id'] as String?,
    name: json['name'] as String?,
    category: json['category'] as String?,
    isOpen: json['is_open'] as bool?,
    subscriptionStatus: json['subscription_status'] as String?,
    kycStatus: json['kyc_status'] as String?,
    trialEndDate: json['trial_end_date'] as String?,
  );

  final bool exists;
  final String? shopId;
  final String? name;
  final String? category;
  final bool? isOpen;
  final String? subscriptionStatus;
  final String? kycStatus;
  final String? trialEndDate;

  bool get isApproved => kycStatus == 'approved';
  bool get isPending => kycStatus == 'pending';
  bool get isRejected => kycStatus == 'rejected';
}

final shopDataProvider = FutureProvider.autoDispose<ShopData>((ref) async {
  final client = ref.watch(apiClientProvider);
  final result = await client.get<Map<String, dynamic>>(
    '/api/v1/shops/mine',
    fromJson: (d) => d as Map<String, dynamic>,
  );
  return result.when(
    success: ShopData.fromJson,
    failure: (AppError e) => throw e,
  );
});

// --- Products ---

class ProductItem {
  const ProductItem({
    required this.id,
    required this.name,
    required this.pricePaise,
    required this.unit,
    required this.stockStatus,
  });

  factory ProductItem.fromJson(Map<String, dynamic> json) => ProductItem(
    id: json['id'] as String,
    name: json['name'] as String,
    pricePaise: json['price_paise'] as int,
    unit: json['unit'] as String,
    stockStatus: json['stock_status'] as String,
  );

  final String id;
  final String name;
  final int pricePaise;
  final String unit;
  final String stockStatus;

  bool get isAvailable => stockStatus == 'available';
}

final productsProvider = FutureProvider.autoDispose
    .family<List<ProductItem>, String>((ref, shopId) async {
      final client = ref.watch(apiClientProvider);
      final result = await client.get<List<ProductItem>>(
        '/api/v1/shops/$shopId/products',
        fromJson: (data) => (data as List)
            .map((e) => ProductItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
      return result.when(
        success: (List<ProductItem> items) => items,
        failure: (AppError e) => throw e,
      );
    });

// --- Orders ---

/// One line on an order.
class ShopOrderLine {
  const ShopOrderLine({
    required this.id,
    required this.name,
    required this.qty,
    required this.pricePaise,
    required this.lineTotalPaise,
    required this.availabilityStatus,
    this.unit,
    this.unavailableReason,
  });

  factory ShopOrderLine.fromJson(Map<String, dynamic> json) => ShopOrderLine(
    id: json['id'] as String,
    name: json['name'] as String,
    qty: json['qty'] as int,
    pricePaise: json['price_paise'] as int,
    lineTotalPaise: json['line_total_paise'] as int,
    availabilityStatus: json['availability_status'] as String,
    unit: json['unit'] as String?,
    unavailableReason: json['unavailable_reason'] as String?,
  );

  final String id;
  final String name;
  final int qty;
  final int pricePaise;
  final int lineTotalPaise;
  final String availabilityStatus;
  final String? unit;
  final String? unavailableReason;

  bool get isUnavailable => availabilityStatus == 'unavailable';
}

/// A row in the shop's order queue.
class ShopOrderSummary {
  const ShopOrderSummary({
    required this.id,
    required this.status,
    required this.itemCount,
    required this.totalPaise,
    required this.paymentMode,
    required this.awaitingPayment,
    this.itemTotalPaise = 0,
    this.deliveryFeePaise = 0,
    this.paymentStatus,
    this.placedAt,
  });

  factory ShopOrderSummary.fromJson(Map<String, dynamic> json) =>
      ShopOrderSummary(
        id: json['id'] as String,
        status: json['status'] as String,
        itemCount: json['item_count'] as int? ?? 0,
        totalPaise: json['total_paise'] as int? ?? 0,
        paymentMode: json['payment_mode'] as String? ?? 'cod',
        awaitingPayment: json['awaiting_payment'] as bool? ?? false,
        itemTotalPaise: json['item_total_paise'] as int? ?? 0,
        deliveryFeePaise: json['delivery_fee_paise'] as int? ?? 0,
        paymentStatus: json['payment_status'] as String?,
        placedAt: json['placed_at'] as String?,
      );

  final String id;
  final String status;
  final int itemCount;
  final int totalPaise;
  final String paymentMode;

  /// An online order nobody has paid for yet. The shop cannot accept it, and
  /// the row has to say so rather than offer a button that fails.
  final bool awaitingPayment;
  final int itemTotalPaise;
  final int deliveryFeePaise;
  final String? paymentStatus;
  final String? placedAt;

  bool get isNew => status == 'PLACED';
  bool get isCod => paymentMode == 'cod';

  /// Last four of the id. Nobody reads a UUID aloud across a counter.
  String get shortRef => id.length <= 4 ? id : id.substring(id.length - 4);
}

/// A single order with its lines, plus what the shop may do about it next.
///
/// The `can*` flags are the server's answer, not the client's guess. The state
/// machine has guards the app would otherwise have to reimplement and keep in
/// step — the packing photo requirement being the one that bites.
class ShopOrderDetail {
  const ShopOrderDetail({
    required this.summary,
    required this.lines,
    required this.hasPackingPhoto,
    required this.canAccept,
    required this.canMarkReady,
    this.availableItemTotalPaise = 0,
    this.pickupCode,
  });

  factory ShopOrderDetail.fromJson(Map<String, dynamic> json) =>
      ShopOrderDetail(
        summary: ShopOrderSummary.fromJson(json),
        lines: ((json['items'] as List?) ?? [])
            .map((e) => ShopOrderLine.fromJson(e as Map<String, dynamic>))
            .toList(),
        hasPackingPhoto: json['has_packing_photo'] as bool? ?? false,
        canAccept: json['can_accept'] as bool? ?? false,
        canMarkReady: json['can_mark_ready'] as bool? ?? false,
        availableItemTotalPaise:
            json['available_item_total_paise'] as int? ?? 0,
        pickupCode: json['pickup_code'] as String?,
      );

  final ShopOrderSummary summary;
  final List<ShopOrderLine> lines;
  final bool hasPackingPhoto;
  final bool canAccept;
  final bool canMarkReady;
  final int availableItemTotalPaise;

  /// What the rider must read out at the counter. Only present once one is
  /// actually on the way.
  final String? pickupCode;

  String get id => summary.id;
  String get status => summary.status;
  bool get isPreparing => status == 'PREPARING';
}

/// Identifies one order. A record so Riverpod's family caching compares by
/// value — two reads of the same order share a request.
typedef ShopOrderRef = ({String shopId, String orderId});

/// The shop's queue: everything still needing attention, newest first.
final shopOrdersProvider = FutureProvider.autoDispose
    .family<List<ShopOrderSummary>, String>((ref, shopId) async {
      final client = ref.watch(apiClientProvider);
      final result = await client.get<List<ShopOrderSummary>>(
        '/api/v1/shops/$shopId/orders',
        fromJson: (data) => (data as List)
            .map((e) => ShopOrderSummary.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
      return result.when(
        success: (List<ShopOrderSummary> orders) => orders,
        failure: (AppError e) => throw e,
      );
    });

final shopOrderDetailProvider = FutureProvider.autoDispose
    .family<ShopOrderDetail, ShopOrderRef>((ref, ref_) async {
      final client = ref.watch(apiClientProvider);
      final result = await client.get<ShopOrderDetail>(
        '/api/v1/shops/${ref_.shopId}/orders/${ref_.orderId}',
        fromJson: (d) => ShopOrderDetail.fromJson(d as Map<String, dynamic>),
      );
      return result.when(
        success: (ShopOrderDetail detail) => detail,
        failure: (AppError e) => throw e,
      );
    });

/// Maps a wire status onto the badge's vocabulary.
///
/// The badge has no `placed` state, so a brand new order borrows `preparing`'s
/// colour and overrides the text — see [shopStatusLabel].
StatusBadgeState shopStatusBadge(String status) => switch (status) {
  'READY_FOR_PICKUP' ||
  'PARTNER_ASSIGNED' ||
  'PARTNER_ARRIVED_AT_SHOP' => StatusBadgeState.readyForPickup,
  'PICKED_UP' || 'OUT_FOR_DELIVERY' => StatusBadgeState.outForDelivery,
  'DELIVERED' || 'COMPLETED' => StatusBadgeState.delivered,
  'CANCELLED_BY_CUSTOMER' ||
  'CANCELLED_BY_SHOP' ||
  'CANCELLED_ITEM_UNAVAILABLE' ||
  'REJECTED_BY_SHOP' => StatusBadgeState.cancelled,
  _ => StatusBadgeState.preparing,
};

/// Wording a shopkeeper would use, not the wire constant.
String shopStatusLabel(String status) => switch (status) {
  'PLACED' => 'New',
  'ACCEPTED_BY_SHOP' || 'PREPARING' => 'Preparing',
  'AWAITING_CUSTOMER_DECISION' => 'Waiting on customer',
  'ON_HOLD' => 'On hold',
  'READY_FOR_PICKUP' => 'Waiting for rider',
  'PARTNER_ASSIGNED' => 'Rider on the way',
  'PARTNER_ARRIVED_AT_SHOP' => 'Rider here',
  'PICKED_UP' || 'OUT_FOR_DELIVERY' => 'Out for delivery',
  'DELIVERED' || 'COMPLETED' => 'Delivered',
  'REJECTED_BY_SHOP' => 'Rejected',
  _ => status.replaceAll('_', ' ').toLowerCase(),
};
