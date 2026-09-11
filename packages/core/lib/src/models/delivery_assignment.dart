import 'package:freezed_annotation/freezed_annotation.dart';

part 'delivery_assignment.freezed.dart';
part 'delivery_assignment.g.dart';

/// Status of a delivery assignment.
enum DeliveryStatus { assigned, pickedUp, inTransit, delivered, failed }

/// Domain model representing a delivery assignment for a rider.
@freezed
abstract class DeliveryAssignment with _$DeliveryAssignment {
  const factory DeliveryAssignment({
    required String id,
    required String orderId,
    required String riderId,
    required DeliveryStatus status,
    required double pickupLatitude,
    required double pickupLongitude,
    required double dropoffLatitude,
    required double dropoffLongitude,
    DateTime? pickedUpAt,
    DateTime? deliveredAt,
  }) = _DeliveryAssignment;

  factory DeliveryAssignment.fromJson(Map<String, dynamic> json) =>
      _$DeliveryAssignmentFromJson(json);
}
