import 'package:freezed_annotation/freezed_annotation.dart';

part 'address.freezed.dart';
part 'address.g.dart';

/// Domain model representing a physical address.
@freezed
abstract class Address with _$Address {
  const factory Address({
    required String id,
    required String userId,
    required String label,
    required String street,
    required String city,
    required String state,
    required String postalCode,
    required double latitude,
    required double longitude,
    @Default(false) bool isDefault,
  }) = _Address;

  factory Address.fromJson(Map<String, dynamic> json) =>
      _$AddressFromJson(json);
}
