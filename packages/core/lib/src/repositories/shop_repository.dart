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
    this.shopCode,
  });

  factory NearbyShop.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String? ?? '';
    final code = json['shop_code'] as String? ??
        (id.isNotEmpty
            ? 'PSL-${id.replaceAll(RegExp(r'\D'), '').padLeft(4, '0').substring(0, 4)}'
            : 'PSL-1001');
    return NearbyShop(
      id: id,
      name: json['name'] as String? ?? 'Passel Store',
      category: json['category'] as String? ?? 'General',
      isOpen: json['is_open'] as bool? ?? true,
      distanceM: (json['distance_m'] as num?)?.toDouble() ?? 500,
      deliveryRadiusKm: json['delivery_radius_km'] as int? ?? 5,
      shopCode: code,
    );
  }

  final String id;
  final String name;
  final String category;
  final bool isOpen;
  final double distanceM;
  final int deliveryRadiusKm;
  final String? shopCode;
}

/// Full shop detail from the detail endpoint.
class ShopDetail {
  const ShopDetail({
    required this.id,
    required this.name,
    required this.category,
    required this.isOpen,
    required this.products,
    this.shopCode,
  });

  factory ShopDetail.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String? ?? '';
    final code = json['shop_code'] as String? ??
        (id.isNotEmpty
            ? 'PSL-${id.replaceAll(RegExp(r'\D'), '').padLeft(4, '0').substring(0, 4)}'
            : 'PSL-1001');
    return ShopDetail(
      id: id,
      name: json['name'] as String? ?? 'Passel Store',
      category: json['category'] as String? ?? 'General',
      isOpen: json['is_open'] as bool? ?? true,
      shopCode: code,
      products: _parseProducts(
        json['products'] as Map<String, dynamic>? ?? {},
      ),
    );
  }

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
  final String? shopCode;
  final Map<String, List<ShopProduct>> products;
}

/// A product within a shop.
class ShopProduct {
  const ShopProduct({
    required this.id,
    required this.name,
    required this.pricePaise,
    required this.stockStatus,
    this.description,
    this.imageUrl,
    this.category,
    this.unit,
  });

  factory ShopProduct.fromJson(Map<String, dynamic> json) => ShopProduct(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        pricePaise: json['price_paise'] as int? ?? 0,
        stockStatus: json['stock_status'] as String? ?? 'available',
        description: json['description'] as String?,
        imageUrl: json['image_url'] as String?,
        category: json['category'] as String?,
        unit: json['unit'] as String? ?? 'piece',
      );

  final String id;
  final String name;
  final int pricePaise;
  final String stockStatus;
  final String? description;
  final String? imageUrl;
  final String? category;
  final String? unit;

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

  Future<Result<List<NearbyShop>>> getEligibleBundleShops(
    String anchorShopId,
  ) =>
      _client.get<List<NearbyShop>>(
        '/api/v1/shops/$anchorShopId/eligible-bundle-shops',
        fromJson: (data) => (data as List)
            .map((e) => NearbyShop.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
