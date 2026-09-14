import 'package:core/core.dart';
import 'package:customer_app/src/services/location_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// --- Auth ---
final supabaseClientProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(supabaseClientProvider).auth.onAuthStateChange;
});

/// Phone OTP send and verify. Behind a provider so onboarding is testable
/// without a live Supabase instance.
final phoneAuthProvider = Provider<PhoneAuth>(
  (ref) => PhoneAuth(auth: ref.watch(supabaseClientProvider).auth),
);

/// Reads the customer's position when they are pinning a delivery address.
/// Behind a provider so tests never touch the platform.
final locationServiceProvider = Provider<CustomerLocationService>(
  (ref) => const CustomerLocationService(),
);

// --- API Client ---
final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

// --- Repositories ---
final customerRepositoryProvider = Provider<CustomerRepository>(
  (ref) => CustomerRepository(ref.watch(apiClientProvider)),
);

final addressRepositoryProvider = Provider<AddressRepository>(
  (ref) => AddressRepository(ref.watch(apiClientProvider)),
);

final shopRepositoryProvider = Provider<ShopRepository>(
  (ref) => ShopRepository(ref.watch(apiClientProvider)),
);

final walletRepositoryProvider = Provider<WalletRepository>(
  (ref) => WalletRepository(ref.watch(apiClientProvider)),
);

final groupOrderRepositoryProvider = Provider<GroupOrderRepository>(
  (ref) => GroupOrderRepository(ref.watch(apiClientProvider)),
);

// --- Wallet Data ---
final walletDataProvider = FutureProvider.autoDispose<WalletData>((ref) async {
  final repo = ref.watch(walletRepositoryProvider);
  final result = await repo.getWallet();
  return result.when(
    success: (WalletData data) => data,
    failure: (AppError error) => throw error,
  );
});

// --- Customer Profile ---
final customerProfileProvider = FutureProvider.autoDispose<CustomerProfile>((
  ref,
) async {
  final repo = ref.watch(customerRepositoryProvider);
  final result = await repo.getProfile();
  return result.when(
    success: (CustomerProfile profile) => profile,
    failure: (AppError error) => throw error,
  );
});

// --- Addresses ---
final addressListProvider = FutureProvider.autoDispose<List<SavedAddress>>((
  ref,
) async {
  final repo = ref.watch(addressRepositoryProvider);
  final result = await repo.listAddresses();
  return result.when(
    success: (List<SavedAddress> addresses) => addresses,
    failure: (AppError error) => throw error,
  );
});

// Active address selection
final activeAddressProvider = StateProvider<SavedAddress?>((ref) => null);

// --- Nearby Shops ---
final nearbyShopsProvider = FutureProvider.autoDispose<List<NearbyShop>>((
  ref,
) async {
  final address = ref.watch(activeAddressProvider);
  if (address == null) return [];
  final repo = ref.watch(shopRepositoryProvider);
  final search = ref.watch(shopSearchQueryProvider);
  final result = await repo.getNearbyShops(lat: 0, lng: 0, search: search);
  return result.when(
    success: (List<NearbyShop> shops) {
      if (search != null && search.trim().isNotEmpty) {
        final q = search.trim().toLowerCase();
        return shops.where((s) {
          final matchName = s.name.toLowerCase().contains(q);
          final matchCat = s.category.toLowerCase().contains(q);
          final matchCode = s.shopCode?.toLowerCase().contains(q) ?? false;
          final matchId = s.id.toLowerCase().contains(q);
          return matchName || matchCat || matchCode || matchId;
        }).toList();
      }
      return shops;
    },
    failure: (AppError error) => throw error,
  );
});

final shopSearchQueryProvider = StateProvider<String?>((ref) => null);

// --- Eligible Bundle Shops within 100m of Anchor Shop ---
final eligibleBundleShopsProvider = FutureProvider.autoDispose
    .family<List<NearbyShop>, String>((ref, anchorShopId) async {
      final repo = ref.watch(shopRepositoryProvider);
      final result = await repo.getEligibleBundleShops(anchorShopId);
      return result.when(
        success: (shops) => shops,
        failure: (_) => <NearbyShop>[],
      );
    });

// --- Shop Detail ---
final shopDetailProvider = FutureProvider.autoDispose
    .family<ShopDetail, String>((ref, shopId) async {
      final repo = ref.watch(shopRepositoryProvider);
      final result = await repo.getShopDetail(shopId);
      return result.when(
        success: (ShopDetail detail) => detail,
        failure: (AppError error) => throw error,
      );
    });

// --- Cart ---
class CartItem {
  const CartItem({
    required this.product,
    required this.quantity,
    this.shopId,
    this.shopName,
  });

  final ShopProduct product;
  final int quantity;
  final String? shopId;
  final String? shopName;

  int get totalPaise => product.pricePaise * quantity;
}

class CartState {
  const CartState({
    this.shopId,
    this.items = const {},
    this.bundledShopIds = const {},
    this.shopNames = const {},
  });

  final String? shopId; // Anchor shop ID
  final Map<String, CartItem> items;
  final Set<String> bundledShopIds;
  final Map<String, String> shopNames;

  String? get anchorShopId => shopId;

  Set<String> get allShopIds {
    final set = <String>{};
    if (shopId != null) set.add(shopId!);
    set.addAll(bundledShopIds);
    for (final item in items.values) {
      if (item.shopId != null) set.add(item.shopId!);
    }
    return set;
  }

  bool get isMultiShop => allShopIds.length > 1;

  Map<String, List<CartItem>> get itemsByShop {
    final map = <String, List<CartItem>>{};
    for (final item in items.values) {
      final sId = item.shopId ?? shopId ?? '';
      map.putIfAbsent(sId, () => []).add(item);
    }
    return map;
  }

  int get itemCount => items.values.fold(0, (s, i) => s + i.quantity);
  int get subtotalPaise => items.values.fold(0, (s, i) => s + i.totalPaise);
  bool get isEmpty => items.isEmpty;
}

class CartNotifier extends StateNotifier<CartState> {
  CartNotifier() : super(const CartState());

  void addProduct(
    String shopId,
    ShopProduct product, {
    String? shopName,
    bool isBundled = false,
  }) {
    if (state.shopId != null &&
        state.shopId != shopId &&
        !isBundled &&
        !state.bundledShopIds.contains(shopId)) {
      return;
    }
    final effectiveShopId = state.shopId ?? shopId;
    final bundled = Set<String>.from(state.bundledShopIds);
    if (effectiveShopId != shopId) {
      bundled.add(shopId);
    }
    final names = Map<String, String>.from(state.shopNames);
    if (shopName != null) {
      names[shopId] = shopName;
    }

    final existing = state.items[product.id];
    final newQty = (existing?.quantity ?? 0) + 1;
    state = CartState(
      shopId: effectiveShopId,
      bundledShopIds: bundled,
      shopNames: names,
      items: {
        ...state.items,
        product.id: CartItem(
          product: product,
          quantity: newQty,
          shopId: shopId,
          shopName: shopName ?? names[shopId],
        ),
      },
    );
  }

  void removeProduct(String productId) {
    final items = Map<String, CartItem>.from(state.items);
    final item = items[productId];
    if (item == null) return;
    if (item.quantity <= 1) {
      items.remove(productId);
    } else {
      items[productId] = CartItem(
        product: item.product,
        quantity: item.quantity - 1,
        shopId: item.shopId,
        shopName: item.shopName,
      );
    }

    if (items.isEmpty) {
      state = const CartState();
      return;
    }

    final remainingShopIds = items.values.map((i) => i.shopId).toSet();
    final remainingBundled = state.bundledShopIds
        .where((id) => remainingShopIds.contains(id))
        .toSet();

    state = CartState(
      shopId: state.shopId,
      bundledShopIds: remainingBundled,
      shopNames: state.shopNames,
      items: items,
    );
  }

  void clearCart() => state = const CartState();

  void clearAndAdd(String shopId, ShopProduct product, {String? shopName}) {
    state = CartState(
      shopId: shopId,
      shopNames: shopName != null ? {shopId: shopName} : const {},
      items: {
        product.id: CartItem(
          product: product,
          quantity: 1,
          shopId: shopId,
          shopName: shopName,
        ),
      },
    );
  }

  bool wouldConflict(String shopId) =>
      state.shopId != null &&
      state.shopId != shopId &&
      !state.bundledShopIds.contains(shopId) &&
      !state.isEmpty;
}

final cartProvider = StateNotifierProvider<CartNotifier, CartState>(
  (ref) => CartNotifier(),
);
