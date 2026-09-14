import 'package:core/src/api/api_client.dart';
import 'package:core/src/errors/result.dart';

/// Order list item.
class OrderSummary {
  const OrderSummary({
    required this.id,
    required this.shopId,
    required this.status,
    required this.itemTotalPaise,
    required this.deliveryFeePaise,
    required this.paymentMode,
    this.createdAt,
    this.walletAmountUsedPaise = 0,
    this.isMultiShop = false,
    this.parentOrderId,
  });

  factory OrderSummary.fromJson(Map<String, dynamic> json) => OrderSummary(
        id: json['id'] as String,
        shopId: json['shop_id'] as String,
        status: json['status'] as String,
        itemTotalPaise: json['item_total_paise'] as int? ?? 0,
        deliveryFeePaise: json['delivery_fee_paise'] as int? ?? 0,
        paymentMode: json['payment_mode'] as String? ?? 'online',
        createdAt: json['created_at'] as String?,
        walletAmountUsedPaise: json['wallet_amount_used_paise'] as int? ?? 0,
        isMultiShop: json['is_multi_shop'] as bool? ?? false,
        parentOrderId: json['parent_order_id'] as String?,
      );

  final String id;
  final String shopId;
  final String status;
  final int itemTotalPaise;
  final int deliveryFeePaise;
  final String paymentMode;
  final String? createdAt;
  final int walletAmountUsedPaise;
  final bool isMultiShop;
  final String? parentOrderId;

  int get totalPaise => itemTotalPaise + deliveryFeePaise;
  int get netPayablePaise => totalPaise - walletAmountUsedPaise;
}

/// Full order detail.
class OrderDetail {
  const OrderDetail({
    required this.id,
    required this.shopId,
    required this.status,
    required this.itemTotalPaise,
    required this.deliveryFeePaise,
    required this.paymentMode,
    required this.items,
    required this.statusHistory,
    required this.photos,
    required this.ratings,
    this.batchingRefundPaise,
    this.deliveryOtp,
    this.walletAmountUsedPaise = 0,
    this.isMultiShop = false,
    this.parentOrderId,
  });

  factory OrderDetail.fromJson(Map<String, dynamic> json) => OrderDetail(
        id: json['id'] as String,
        shopId: json['shop_id'] as String,
        status: json['status'] as String,
        itemTotalPaise: json['item_total_paise'] as int? ?? 0,
        deliveryFeePaise: json['delivery_fee_paise'] as int? ?? 0,
        paymentMode: json['payment_mode'] as String? ?? 'online',
        walletAmountUsedPaise: json['wallet_amount_used_paise'] as int? ?? 0,
        isMultiShop: json['is_multi_shop'] as bool? ?? false,
        parentOrderId: json['parent_order_id'] as String?,
        items: (json['items'] as List?)
                ?.map(
                  (e) => OrderDetailItem.fromJson(
                    e as Map<String, dynamic>,
                  ),
                )
                .toList() ??
            [],
        statusHistory: (json['status_history'] as List?)
                ?.map(
                  (e) => StatusHistoryEntry.fromJson(
                    e as Map<String, dynamic>,
                  ),
                )
                .toList() ??
            [],
        photos: (json['photos'] as List?)
                ?.map(
                  (e) => OrderPhotoEntry.fromJson(
                    e as Map<String, dynamic>,
                  ),
                )
                .toList() ??
            [],
        ratings: (json['ratings'] as List?)
                ?.map(
                  (e) => RatingEntry.fromJson(
                    e as Map<String, dynamic>,
                  ),
                )
                .toList() ??
            [],
        batchingRefundPaise: json['batching_refund_paise'] as int?,
        deliveryOtp: json['delivery_otp'] as String?,
      );

  final String id;
  final String shopId;
  final String status;
  final int itemTotalPaise;
  final int deliveryFeePaise;
  final String paymentMode;
  final List<OrderDetailItem> items;
  final List<StatusHistoryEntry> statusHistory;
  final List<OrderPhotoEntry> photos;
  final List<RatingEntry> ratings;
  final int? batchingRefundPaise;
  final String? deliveryOtp;
  final int walletAmountUsedPaise;
  final bool isMultiShop;
  final String? parentOrderId;

  int get totalPaise => itemTotalPaise + deliveryFeePaise;
  int get netPayablePaise => totalPaise - walletAmountUsedPaise;
}

class OrderDetailItem {
  const OrderDetailItem({
    required this.id,
    required this.qty,
    required this.pricePaise,
    required this.availability,
  });

  factory OrderDetailItem.fromJson(Map<String, dynamic> json) =>
      OrderDetailItem(
        id: json['id'] as String,
        qty: json['qty'] as int,
        pricePaise: json['price_at_order_time_paise'] as int,
        availability: json['availability_status'] as String,
      );

  final String id;
  final int qty;
  final int pricePaise;
  final String availability;
}

class StatusHistoryEntry {
  const StatusHistoryEntry({
    required this.status,
    this.createdAt,
  });

  factory StatusHistoryEntry.fromJson(Map<String, dynamic> json) =>
      StatusHistoryEntry(
        status: json['status'] as String,
        createdAt: json['created_at'] as String?,
      );

  final String status;
  final String? createdAt;
}

class OrderPhotoEntry {
  const OrderPhotoEntry({
    required this.stage,
    required this.photoUrl,
    this.capturedBy,
    this.createdAt,
  });

  factory OrderPhotoEntry.fromJson(Map<String, dynamic> json) =>
      OrderPhotoEntry(
        stage: json['stage'] as String,
        photoUrl: json['photo_url'] as String,
        capturedBy: json['captured_by'] as String?,
        createdAt: json['created_at'] as String?,
      );

  final String stage;
  final String photoUrl;
  final String? capturedBy;
  final String? createdAt;
}

class RatingEntry {
  const RatingEntry({
    required this.entityType,
    required this.score,
    this.comment,
  });

  factory RatingEntry.fromJson(Map<String, dynamic> json) => RatingEntry(
        entityType: json['rated_entity_type'] as String,
        score: json['score'] as int,
        comment: json['comment'] as String?,
      );

  final String entityType;
  final int score;
  final String? comment;
}

/// Tracking data.
class TrackingData {
  const TrackingData({
    required this.orderId,
    required this.status,
    required this.statusHistory,
    this.partnerId,
    this.deliveryOtp,
    this.handoverInitiatedAt,
    this.verificationDeadline,
    this.verificationStatus = 'NOT_INITIATED',
    this.remainingSeconds = 0,
    this.additionWindowStatus = 'ADDITION_OPEN',
    this.canAddMore = false,
  });

  factory TrackingData.fromJson(Map<String, dynamic> json) => TrackingData(
        orderId: json['order_id'] as String,
        status: json['status'] as String,
        statusHistory: (json['status_history'] as List?)
                ?.map(
                  (e) => StatusHistoryEntry.fromJson(
                    e as Map<String, dynamic>,
                  ),
                )
                .toList() ??
            [],
        partnerId: json['partner_id'] as String?,
        deliveryOtp: json['delivery_otp'] as String?,
        handoverInitiatedAt: json['handover_initiated_at'] as String?,
        verificationDeadline: json['verification_deadline'] as String?,
        verificationStatus: json['verification_status'] as String? ?? 'NOT_INITIATED',
        remainingSeconds: json['remaining_seconds'] as int? ?? 0,
        additionWindowStatus: json['addition_window_status'] as String? ?? 'ADDITION_OPEN',
        canAddMore: json['can_add_more'] as bool? ?? false,
      );

  final String orderId;
  final String status;
  final List<StatusHistoryEntry> statusHistory;
  final String? partnerId;
  final String? deliveryOtp;
  final String? handoverInitiatedAt;
  final String? verificationDeadline;
  final String verificationStatus;
  final int remainingSeconds;
  final String additionWindowStatus;
  final bool canAddMore;
}

/// Repository for orders.
class OrderRepository {
  OrderRepository(this._client);
  final ApiClient _client;

  Future<Result<List<OrderSummary>>> listOrders({
    String? status,
    int limit = 20,
    int offset = 0,
  }) =>
      _client.get<List<OrderSummary>>(
        '/api/v1/orders/history',
        queryParameters: {
          if (status != null) 'status': status,
          'limit': limit.toString(),
          'offset': offset.toString(),
        },
        fromJson: (data) {
          final map = data as Map<String, dynamic>;
          return (map['orders'] as List)
              .map(
                (e) => OrderSummary.fromJson(
                  e as Map<String, dynamic>,
                ),
              )
              .toList();
        },
      );

  Future<Result<OrderDetail>> getDetail(String orderId) =>
      _client.get<OrderDetail>(
        '/api/v1/orders/detail/$orderId',
        fromJson: (data) =>
            OrderDetail.fromJson(data as Map<String, dynamic>),
      );

  Future<Result<TrackingData>> getTracking(String orderId) =>
      _client.get<TrackingData>(
        '/api/v1/orders/track/$orderId',
        fromJson: (data) =>
            TrackingData.fromJson(data as Map<String, dynamic>),
      );

  Future<Result<Map<String, dynamic>>> rateOrder({
    required String orderId,
    required String entityType,
    required int score,
    String? comment,
  }) =>
      _client.post<Map<String, dynamic>>(
        '/api/v1/orders/rate/$orderId',
        data: {
          'rated_entity_type': entityType,
          'score': score,
          if (comment != null) 'comment': comment,
        },
        fromJson: (data) => data as Map<String, dynamic>,
      );

  Future<Result<Map<String, dynamic>>> raiseDispute({
    required String orderId,
    required String reason,
    String? comment,
  }) =>
      _client.post<Map<String, dynamic>>(
        '/api/v1/orders/dispute/$orderId',
        data: {
          'reason': reason,
          if (comment != null) 'comment': comment,
        },
        fromJson: (data) => data as Map<String, dynamic>,
      );

  /// Delivery verification: Customer verifies items or reports issue.
  /// If action == 'everything_correct', delivery finalizes immediately.
  Future<Result<Map<String, dynamic>>> verifyItems({
    required String orderId,
    required String action,
  }) =>
      _client.post<Map<String, dynamic>>(
        '/api/v1/orders/$orderId/verify-items',
        data: {'action': action},
        fromJson: (data) => data as Map<String, dynamic>,
      );

  /// Customer reports missing, wrong, damaged, or expired item.
  Future<Result<Map<String, dynamic>>> reportIssue({
    required String orderId,
    required String issueType,
    required String orderItemId,
    String? customerNotes,
    String? evidencePhotoUrl,
  }) =>
      _client.post<Map<String, dynamic>>(
        '/api/v1/orders/$orderId/report-issue',
        data: {
          'issue_type': issueType,
          'order_item_id': orderItemId,
          if (customerNotes != null) 'customer_notes': customerNotes,
          if (evidencePhotoUrl != null) 'evidence_photo_url': evidencePhotoUrl,
        },
        fromJson: (data) => data as Map<String, dynamic>,
      );

  /// Check whether active order is eligible for adding more items.
  Future<Result<Map<String, dynamic>>> getAdditionStatus(String orderId) =>
      _client.get<Map<String, dynamic>>(
        '/api/v1/orders/$orderId/addition-status',
        fromJson: (data) => data as Map<String, dynamic>,
      );

  /// Add items to active order before packing is sealed.
  Future<Result<Map<String, dynamic>>> createAddition({
    required String orderId,
    required List<Map<String, dynamic>> items,
    int walletAmountToUsePaise = 0,
    String paymentMode = 'online',
    String? idempotencyKey,
  }) =>
      _client.post<Map<String, dynamic>>(
        '/api/v1/orders/$orderId/additions',
        data: {
          'items': items,
          'wallet_amount_to_use_paise': walletAmountToUsePaise,
          'payment_mode': paymentMode,
          if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
        },
        fromJson: (data) => data as Map<String, dynamic>,
      );

  /// Shop closes addition window when packing starts / package sealed.
  Future<Result<Map<String, dynamic>>> closeAdditions(String orderId) =>
      _client.post<Map<String, dynamic>>(
        '/api/v1/orders/$orderId/close-additions',
        fromJson: (data) => data as Map<String, dynamic>,
      );
}
