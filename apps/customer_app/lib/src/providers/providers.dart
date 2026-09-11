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
    success: (List<NearbyShop> shops) => shops,
    failure: (AppError error) => throw error,
  );
});

final shopSearchQueryProvider = StateProvider<String?>((ref) => null);

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
  const CartItem({required this.product, required this.quantity});
  final ShopProduct product;
  final int quantity;

  int get totalPaise => product.pricePaise * quantity;
}

class CartState {
  const CartState({this.shopId, this.items = const {}});
  final String? shopId;
  final Map<String, CartItem> items;

  int get itemCount => items.values.fold(0, (s, i) => s + i.quantity);
  int get subtotalPaise => items.values.fold(0, (s, i) => s + i.totalPaise);
  bool get isEmpty => items.isEmpty;
}

class CartNotifier extends StateNotifier<CartState> {
  CartNotifier() : super(const CartState());

  void addProduct(String shopId, ShopProduct product) {
    if (state.shopId != null && state.shopId != shopId) {
      return;
    }
    final existing = state.items[product.id];
    final newQty = (existing?.quantity ?? 0) + 1;
    state = CartState(
      shopId: shopId,
      items: {
        ...state.items,
        product.id: CartItem(product: product, quantity: newQty),
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
      );
    }
    state = CartState(
      shopId: items.isEmpty ? null : state.shopId,
      items: items,
    );
  }

  void clearCart() => state = const CartState();

  void clearAndAdd(String shopId, ShopProduct product) {
    state = CartState(
      shopId: shopId,
      items: {product.id: CartItem(product: product, quantity: 1)},
    );
  }

  bool wouldConflict(String shopId) =>
      state.shopId != null && state.shopId != shopId && !state.isEmpty;
}

final cartProvider = StateNotifierProvider<CartNotifier, CartState>(
  (ref) => CartNotifier(),
);
