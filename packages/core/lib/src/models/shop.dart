import 'package:freezed_annotation/freezed_annotation.dart';

part 'shop.freezed.dart';
part 'shop.g.dart';

/// Domain model representing a shop/store on the platform.
@freezed
abstract class Shop with _$Shop {
  const factory Shop({
    required String id,
    required String name,
    required String ownerId,
    required String address,
    required double latitude,
    required double longitude,
    String? imageUrl,
    @Default(true) bool isActive,
  }) = _Shop;

  factory Shop.fromJson(Map<String, dynamic> json) => _$ShopFromJson(json);
}
