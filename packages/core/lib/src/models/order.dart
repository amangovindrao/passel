import 'package:freezed_annotation/freezed_annotation.dart';

part 'order.freezed.dart';
part 'order.g.dart';

/// Order status lifecycle.
/// Order status lifecycle.
enum OrderStatus {
  pending,
  confirmed,
  preparing,
  dispatched,
  delivered,
  cancelled,
}

/// Domain model representing a customer order.
@freezed
abstract class Order with _$Order {
  const factory Order({
    required String id,
    required String customerId,
    required String shopId,
    required OrderStatus status,
    required double totalAmount,
    required DateTime createdAt,
    String? deliveryAssignmentId,
  }) = _Order;

  factory Order.fromJson(Map<String, dynamic> json) => _$OrderFromJson(json);
}
