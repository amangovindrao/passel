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
  });

  factory OrderSummary.fromJson(Map<String, dynamic> json) => OrderSummary(
        id: json['id'] as String,
        shopId: json['shop_id'] as String,
        status: json['status'] as String,
        itemTotalPaise: json['item_total_paise'] as int,
        deliveryFeePaise: json['delivery_fee_paise'] as int,
        paymentMode: json['payment_mode'] as String,
        createdAt: json['created_at'] as String?,
      );

  final String id;
  final String shopId;
  final String status;
  final int itemTotalPaise;
  final int deliveryFeePaise;
  final String paymentMode;
  final String? createdAt;

  int get totalPaise => itemTotalPaise + deliveryFeePaise;
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
  });

  factory OrderDetail.fromJson(Map<String, dynamic> json) => OrderDetail(
        id: json['id'] as String,
        shopId: json['shop_id'] as String,
        status: json['status'] as String,
        itemTotalPaise: json['item_total_paise'] as int,
        deliveryFeePaise: json['delivery_fee_paise'] as int,
        paymentMode: json['payment_mode'] as String,
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
      );

  final String orderId;
  final String status;
  final List<StatusHistoryEntry> statusHistory;
  final String? partnerId;
  final String? deliveryOtp;
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
}
