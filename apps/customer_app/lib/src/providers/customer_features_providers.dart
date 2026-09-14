import 'package:core/core.dart';
import 'package:customer_app/src/providers/order_providers.dart';
import 'package:customer_app/src/providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui_kit/ui_kit.dart';

// --- 1. Favorite Shops Provider ---

class FavoriteShopsNotifier extends StateNotifier<Set<String>> {
  FavoriteShopsNotifier() : super(const {'shop_1', '1'});

  void toggleFavorite(String shopId) {
    if (state.contains(shopId)) {
      state = Set.from(state)..remove(shopId);
    } else {
      state = Set.from(state)..add(shopId);
    }
  }

  bool isFavorite(String shopId) => state.contains(shopId);
}

final favoriteShopsProvider =
    StateNotifierProvider<FavoriteShopsNotifier, Set<String>>(
      (ref) => FavoriteShopsNotifier(),
    );

// --- 2. Monthly Ration Provider ---

class MonthlyRationItem {
  const MonthlyRationItem({
    required this.id,
    required this.name,
    required this.quantityText,
    required this.pricePaise,
  });

  final String id;
  final String name;
  final String quantityText;
  final int pricePaise;

  double get priceRupees => pricePaise / 100.0;
}

class MonthlyRationState {
  const MonthlyRationState({
    required this.nextDeliveryDate,
    required this.status, // 'active', 'paused', 'skipped'
    required this.items,
  });

  final DateTime nextDeliveryDate;
  final String status;
  final List<MonthlyRationItem> items;

  int get itemCount => items.length;
  int get totalPaise => items.fold(0, (sum, i) => sum + i.pricePaise);
  double get totalRupees => totalPaise / 100.0;
  bool get isActive => status == 'active';
  bool get isPaused => status == 'paused';
  bool get isSkipped => status == 'skipped';
}

class MonthlyRationNotifier extends StateNotifier<MonthlyRationState> {
  MonthlyRationNotifier()
    : super(
        MonthlyRationState(
          nextDeliveryDate: DateTime.now().add(const Duration(days: 18)),
          status: 'active',
          items: const [
            MonthlyRationItem(
              id: 'r1',
              name: 'Basmati Rice',
              quantityText: '5 kg',
              pricePaise: 48000,
            ),
            MonthlyRationItem(
              id: 'r2',
              name: 'Chakki Atta',
              quantityText: '10 kg',
              pricePaise: 42000,
            ),
            MonthlyRationItem(
              id: 'r3',
              name: 'Refined Oil',
              quantityText: '2 L',
              pricePaise: 27000,
            ),
            MonthlyRationItem(
              id: 'r4',
              name: 'Toor Dal',
              quantityText: '2 kg',
              pricePaise: 31000,
            ),
            MonthlyRationItem(
              id: 'r5',
              name: 'Sugar & Tea',
              quantityText: '2 kg + 500g',
              pricePaise: 24000,
            ),
          ],
        ),
      );

  void pause() => state = MonthlyRationState(
    nextDeliveryDate: state.nextDeliveryDate,
    status: 'paused',
    items: state.items,
  );

  void resume() => state = MonthlyRationState(
    nextDeliveryDate: state.nextDeliveryDate,
    status: 'active',
    items: state.items,
  );

  void skipThisMonth() => state = MonthlyRationState(
    nextDeliveryDate: state.nextDeliveryDate.add(const Duration(days: 30)),
    status: 'skipped',
    items: state.items,
  );

  void configureDefaults() => resume();
}

final monthlyRationProvider =
    StateNotifierProvider<MonthlyRationNotifier, MonthlyRationState>(
      (ref) => MonthlyRationNotifier(),
    );

// --- 3. Product Request Provider ("Can't find it? Ask nearby shops") ---

class ProductRequestItem {
  const ProductRequestItem({
    required this.id,
    required this.productName,
    required this.status, // 'submitted', 'available', 'unavailable'
    required this.createdAt,
    this.matchedShopName,
    this.pricePaise,
    this.notes,
  });

  final String id;
  final String productName;
  final String status;
  final String? matchedShopName;
  final int? pricePaise;
  final String? notes;
  final DateTime createdAt;
}

class ProductRequestNotifier extends StateNotifier<List<ProductRequestItem>> {
  ProductRequestNotifier() : super(const []);

  void addRequest(ProductRequestItem item) {
    state = [item, ...state];
  }
}

final productRequestProvider =
    StateNotifierProvider<ProductRequestNotifier, List<ProductRequestItem>>(
      (ref) => ProductRequestNotifier(),
    );

// --- 4. Community / Society Group Order & Private Cart Mode ---

class GroupOrderState {
  const GroupOrderState({
    this.session,
    this.isLoading = false,
    this.errorMessage,
  });

  final GroupOrderSessionModel? session;
  final bool isLoading;
  final String? errorMessage;

  bool get isPrivateCartMode => session?.privateCartMode ?? false;
  bool get isLocked => session?.isLocked ?? false;

  GroupOrderState copyWith({
    GroupOrderSessionModel? session,
    bool? isLoading,
    String? errorMessage,
  }) {
    return GroupOrderState(
      session: session ?? this.session,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

class GroupOrderNotifier extends StateNotifier<GroupOrderState> {
  GroupOrderNotifier(this._repository) : super(const GroupOrderState()) {
    _initDemoSession();
  }

  final GroupOrderRepository _repository;

  void _initDemoSession() {
    state = GroupOrderState(
      session: GroupOrderSessionModel(
        id: 'demo-society-session-101',
        creatorId: 'user-aman',
        societyName: 'Palm Heights Tower B',
        status: 'OPEN',
        privateCartMode: false,
        closesAt: DateTime.now().add(const Duration(minutes: 18)),
        progress: const GroupOrderProgressModel(
          memberCount: 4,
          shopCount: 3,
          cartsReadyCount: 3,
          paymentsCompletedCount: 2,
          statusText: '3 shops preparing • 4 members joined',
          deliverySavingsPaise: 6000,
          groupTotalPaise: 48000,
        ),
        members: const [
          GroupOrderMemberModel(
            id: 'member-1',
            userId: 'current-user-id',
            name: 'Aman (You)',
            isCreator: true,
            status: 'ready',
            paymentStatus: 'completed',
            subtotalPaise: 12000,
            paidAmountPaise: 12000,
            walletAmountUsedPaise: 2000,
            items: [
              GroupOrderCartItemModel(
                id: 'item-1',
                shopId: 'shop-sharma',
                shopName: 'Sharma Store',
                productId: 'prod-milk',
                productName: 'Amul Gold Milk 500ml',
                qty: 2,
                priceAtAdditionPaise: 3000,
                subtotalPaise: 6000,
              ),
              GroupOrderCartItemModel(
                id: 'item-2',
                shopId: 'shop-gupta',
                shopName: 'Gupta Dairy',
                productId: 'prod-bread',
                productName: 'Harvest Brown Bread',
                qty: 1,
                priceAtAdditionPaise: 6000,
                subtotalPaise: 6000,
              ),
            ],
          ),
          GroupOrderMemberModel(
            id: 'member-2',
            userId: 'user-riya',
            name: 'Riya',
            isCreator: false,
            status: 'ready',
            paymentStatus: 'completed',
            subtotalPaise: 16000,
            paidAmountPaise: 16000,
            items: [
              GroupOrderCartItemModel(
                id: 'item-3',
                shopId: 'shop-sharma',
                shopName: 'Sharma Store',
                productId: 'prod-eggs',
                productName: 'Farm Fresh Eggs (6 pcs)',
                qty: 2,
                priceAtAdditionPaise: 8000,
                subtotalPaise: 16000,
              ),
            ],
          ),
          GroupOrderMemberModel(
            id: 'member-3',
            userId: 'user-vikram',
            name: 'Vikram',
            isCreator: false,
            status: 'ready',
            paymentStatus: 'pending',
            subtotalPaise: 20000,
            items: [
              GroupOrderCartItemModel(
                id: 'item-4',
                shopId: 'shop-cake',
                shopName: 'Bake & Flake',
                productId: 'prod-cake',
                productName: 'Choco Truffle Cake 500g',
                qty: 1,
                priceAtAdditionPaise: 20000,
                subtotalPaise: 20000,
              ),
            ],
          ),
        ],
        myCart: const [
          GroupOrderCartItemModel(
            id: 'item-1',
            shopId: 'shop-sharma',
            shopName: 'Sharma Store',
            productId: 'prod-milk',
            productName: 'Amul Gold Milk 500ml',
            qty: 2,
            priceAtAdditionPaise: 3000,
            subtotalPaise: 6000,
          ),
          GroupOrderCartItemModel(
            id: 'item-2',
            shopId: 'shop-gupta',
            shopName: 'Gupta Dairy',
            productId: 'prod-bread',
            productName: 'Harvest Brown Bread',
            qty: 1,
            priceAtAdditionPaise: 6000,
            subtotalPaise: 6000,
          ),
        ],
        mySubtotalPaise: 12000,
      ),
    );
  }

  Future<void> togglePrivacy({required bool enable, bool confirmDisable = false}) async {
    final currentSession = state.session;
    if (currentSession == null) return;
    if (currentSession.isLocked) {
      state = state.copyWith(errorMessage: 'Privacy settings are locked once order is finalized.');
      return;
    }
    if (!enable && currentSession.privateCartMode && !confirmDisable) {
      state = state.copyWith(errorMessage: 'Disabling Private Cart Mode requires explicit confirmation.');
      return;
    }

    // Deterministic state update
    final updatedSession = GroupOrderSessionModel(
      id: currentSession.id,
      creatorId: currentSession.creatorId,
      deliveryAddressId: currentSession.deliveryAddressId,
      societyName: currentSession.societyName,
      status: currentSession.status,
      privateCartMode: enable,
      closesAt: currentSession.closesAt,
      progress: currentSession.progress,
      members: currentSession.members,
      myCart: currentSession.myCart,
      mySubtotalPaise: currentSession.mySubtotalPaise,
    );
    state = state.copyWith(session: updatedSession, errorMessage: null);

    // Call backend
    await _repository.togglePrivacy(
      currentSession.id,
      enable: enable,
      confirmDisable: confirmDisable,
    );
  }

  void lockSession() {
    final currentSession = state.session;
    if (currentSession == null) return;
    state = state.copyWith(
      session: GroupOrderSessionModel(
        id: currentSession.id,
        creatorId: currentSession.creatorId,
        deliveryAddressId: currentSession.deliveryAddressId,
        societyName: currentSession.societyName,
        status: 'LOCKED',
        privateCartMode: currentSession.privateCartMode,
        closesAt: currentSession.closesAt,
        progress: currentSession.progress,
        members: currentSession.members,
        myCart: currentSession.myCart,
        mySubtotalPaise: currentSession.mySubtotalPaise,
      ),
    );
  }

  Future<void> payMyCart({int walletAmountToUsePaise = 0, String paymentMode = 'online'}) async {
    final currentSession = state.session;
    if (currentSession == null) return;
    state = state.copyWith(isLoading: true, errorMessage: null);
    final result = await _repository.payCart(
      currentSession.id,
      walletAmountToUsePaise: walletAmountToUsePaise,
      paymentMode: paymentMode,
    );
    result.when(
      success: (updated) {
        state = state.copyWith(session: updated, isLoading: false);
      },
      failure: (err) {
        state = state.copyWith(isLoading: false, errorMessage: err.message);
      },
    );
  }

  Future<void> captainPayAll({int walletAmountToUsePaise = 0, String paymentMode = 'online'}) async {
    final currentSession = state.session;
    if (currentSession == null) return;
    state = state.copyWith(isLoading: true, errorMessage: null);
    final result = await _repository.captainPayAll(
      currentSession.id,
      walletAmountToUsePaise: walletAmountToUsePaise,
      paymentMode: paymentMode,
    );
    result.when(
      success: (updated) {
        state = state.copyWith(session: updated, isLoading: false);
      },
      failure: (err) {
        state = state.copyWith(isLoading: false, errorMessage: err.message);
      },
    );
  }
}

final groupOrderStateProvider =
    StateNotifierProvider<GroupOrderNotifier, GroupOrderState>((ref) {
      final repo = ref.watch(groupOrderRepositoryProvider);
      return GroupOrderNotifier(repo);
    });

final isPrivateCartModeActiveProvider = Provider<bool>((ref) {
  return ref.watch(groupOrderStateProvider).isPrivateCartMode;
});

class CommunityBatchInfo {
  const CommunityBatchInfo({
    required this.societyName,
    required this.neighborsCount,
    required this.discountPaise,
    required this.etaText,
    this.isJoined = false,
  });

  final String societyName;
  final int neighborsCount;
  final int discountPaise;
  final String etaText;
  final bool isJoined;

  double get discountRupees => discountPaise / 100.0;
}

class CommunityBatchNotifier extends StateNotifier<CommunityBatchInfo> {
  CommunityBatchNotifier()
    : super(
        const CommunityBatchInfo(
          societyName: 'Palm Heights Tower B',
          neighborsCount: 7,
          discountPaise: 1000,
          etaText: 'Slot 6:30 PM - 7:30 PM',
        ),
      );

  void toggleJoin() {
    state = CommunityBatchInfo(
      societyName: state.societyName,
      neighborsCount: state.neighborsCount + (state.isJoined ? -1 : 1),
      discountPaise: state.discountPaise,
      etaText: state.etaText,
      isJoined: !state.isJoined,
    );
  }
}

final communityBatchProvider =
    StateNotifierProvider<CommunityBatchNotifier, CommunityBatchInfo>(
      (ref) => CommunityBatchNotifier(),
    );

// --- 5. One-Tap Reorder Action ---

Future<void> triggerOneTapReorder({
  required BuildContext context,
  required WidgetRef ref,
  String? orderId,
  String? shopId,
  String? shopName,
}) async {
  try {
    var targetOrderId = orderId;
    var targetShopId = shopId;
    final targetShopName = shopName;

    if (targetOrderId == null || targetShopId == null) {
      final orders = ref.read(pastOrdersProvider).valueOrNull;
      if (orders != null && orders.isNotEmpty) {
        final last = orders.first;
        targetOrderId = last.id;
        targetShopId = last.shopId;
      }
    }

    if (targetOrderId == null || targetShopId == null) {
      if (context.mounted) {
        context.push('/orders');
      }
      return;
    }

    final orderDetail = await ref.read(
      orderDetailProvider(targetOrderId).future,
    );
    final cart = ref.read(cartProvider.notifier);

    for (final item in orderDetail.items) {
      final product = ShopProduct(
        id: item.id,
        name: 'Item #${item.id.length >= 4 ? item.id.substring(0, 4) : item.id}',
        pricePaise: item.pricePaise,
        stockStatus: 'available',
      );
      cart.addProduct(
        targetShopId,
        product,
        shopName: targetShopName,
        isBundled: true,
      );
    }

    if (context.mounted) {
      AppSnackbar.show(
        context,
        message: 'Reorder items added to your cart! 🛒',
        variant: AppSnackbarVariant.success,
      );
      context.push('/cart');
    }
  } on Exception catch (_) {
    if (context.mounted) {
      context.push('/orders');
    }
  }
}

// --- 6. Theme Personality (Classic Minimalist Default vs Pinkie Cute for Girls) ---

enum CustomerThemePersonality {
  classic,
  pinkie,
}

class CustomerThemePersonalityNotifier
    extends StateNotifier<CustomerThemePersonality> {
  CustomerThemePersonalityNotifier() : super(CustomerThemePersonality.classic) {
    _loadPreference();
  }

  static const _prefKey = 'paasel_customer_theme_personality';

  Future<void> _loadPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final val = prefs.getString(_prefKey);
      if (val == 'pinkie') {
        state = CustomerThemePersonality.pinkie;
      } else {
        state = CustomerThemePersonality.classic;
      }
    } catch (_) {}
  }

  Future<void> setPersonality(CustomerThemePersonality personality) async {
    state = personality;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, personality.name);
    } catch (_) {}
  }

  void toggle() {
    final next = state == CustomerThemePersonality.classic
        ? CustomerThemePersonality.pinkie
        : CustomerThemePersonality.classic;
    setPersonality(next);
  }
}

final customerThemePersonalityProvider = StateNotifierProvider<
    CustomerThemePersonalityNotifier, CustomerThemePersonality>(
  (ref) => CustomerThemePersonalityNotifier(),
);

final isPinkieThemeActiveProvider = Provider<bool>((ref) {
  return ref.watch(customerThemePersonalityProvider) ==
      CustomerThemePersonality.pinkie;
});

