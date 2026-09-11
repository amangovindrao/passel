import 'package:freezed_annotation/freezed_annotation.dart';

part 'product.freezed.dart';
part 'product.g.dart';

/// Domain model representing a product available in a shop.
@freezed
abstract class Product with _$Product {
  const factory Product({
    required String id,
    required String shopId,
    required String name,
    required String description,
    required double price,
    String? imageUrl,
    @Default(true) bool isAvailable,
  }) = _Product;

  factory Product.fromJson(Map<String, dynamic> json) =>
      _$ProductFromJson(json);
}
