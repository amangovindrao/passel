import 'package:core/src/api/api_client.dart';
import 'package:core/src/errors/result.dart';

/// Shop data from the nearby endpoint.
class NearbyShop {
  const NearbyShop({
    required this.id,
    required this.name,
    required this.category,
    required this.isOpen,
    required this.distanceM,
    required this.deliveryRadiusKm,
  });

  factory NearbyShop.fromJson(Map<String, dynamic> json) => NearbyShop(
        id: json['id'] as String,
        name: json['name'] as String,
        category: json['category'] as String,
        isOpen: json['is_open'] as bool,
        distanceM: (json['distance_m'] as num).toDouble(),
        deliveryRadiusKm: json['delivery_radius_km'] as int,
      );

  final String id;
  final String name;
  final String category;
  final bool isOpen;
  final double distanceM;
  final int deliveryRadiusKm;
}

/// Full shop detail from the detail endpoint.
class ShopDetail {
  const ShopDetail({
    required this.id,
    required this.name,
    required this.category,
    required this.isOpen,
    required this.products,
  });

  factory ShopDetail.fromJson(Map<String, dynamic> json) => ShopDetail(
        id: json['id'] as String,
        name: json['name'] as String,
        category: json['category'] as String,
        isOpen: json['is_open'] as bool,
        products: _parseProducts(
          json['products'] as Map<String, dynamic>? ?? {},
        ),
      );

  static Map<String, List<ShopProduct>> _parseProducts(
    Map<String, dynamic> raw,
  ) {
    return raw.map((key, value) => MapEntry(
          key,
          (value as List)
              .map((e) => ShopProduct.fromJson(e as Map<String, dynamic>))
              .toList(),
        ));
  }

  final String id;
  final String name;
  final String category;
  final bool isOpen;
  final Map<String, List<ShopProduct>> products;
}

/// A product within a shop.
class ShopProduct {
  const ShopProduct({
    required this.id,
    required this.name,
    required this.pricePaise,
    required this.stockStatus,
  });

  factory ShopProduct.fromJson(Map<String, dynamic> json) => ShopProduct(
        id: json['id'] as String,
        name: json['name'] as String,
        pricePaise: json['price_paise'] as int,
        stockStatus: json['stock_status'] as String,
      );

  final String id;
  final String name;
  final int pricePaise;
  final String stockStatus;

  bool get isAvailable => stockStatus == 'available';
}

/// Repository for shop discovery and detail.
class ShopRepository {
  ShopRepository(this._client);
  final ApiClient _client;

  Future<Result<List<NearbyShop>>> getNearbyShops({
    required double lat,
    required double lng,
    String? search,
  }) {
    final params = <String, dynamic>{
      'lat': lat.toString(),
      'lng': lng.toString(),
      if (search != null && search.isNotEmpty) 'search': search,
    };
    return _client.get<List<NearbyShop>>(
      '/api/v1/shops/nearby',
      queryParameters: params,
      fromJson: (data) => (data as List)
          .map((e) => NearbyShop.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<Result<ShopDetail>> getShopDetail(String shopId) =>
      _client.get<ShopDetail>(
        '/api/v1/shops/$shopId',
        fromJson: (data) => ShopDetail.fromJson(data as Map<String, dynamic>),
      );
}
