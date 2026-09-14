import 'package:core/core.dart';
import 'package:customer_app/src/providers/customer_features_providers.dart';
import 'package:customer_app/src/providers/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ui_kit/ui_kit.dart';

/// Home screen: address selector, wallet quick-pill, contextual banner,
/// category pills, shop list with favorites, and frosted glass bottom bar.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _searchController = TextEditingController();
  String? _selectedCategory;
  bool _onlyFavorites = false;

  final _categories = const [
    ('All', Icons.grid_view_rounded),
    ('Kirana', Icons.storefront_rounded),
    ('Medical', Icons.local_pharmacy_rounded),
    ('Dairy & Bakery', Icons.cake_rounded),
    ('Fresh Veggies', Icons.eco_rounded),
  ];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shopsAsync = ref.watch(nearbyShopsProvider);
    final activeAddress = ref.watch(activeAddressProvider);
    final favShopIds = ref.watch(favoriteShopsProvider);
    final isPinkie = ref.watch(isPinkieThemeActiveProvider);

    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        title: GestureDetector(
          onTap: _showAddressSheet,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.location_on, size: 18, color: AppColors.gold),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  activeAddress?.addressText ?? 'Select address',
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.label,
                ),
              ),
              const Icon(Icons.keyboard_arrow_down, size: 18),
            ],
          ),
        ),
        actions: [
          Consumer(
            builder: (context, ref, _) {
              final walletAsync = ref.watch(walletDataProvider);
              final bal = walletAsync.valueOrNull?.balanceRupees ?? 0.0;
              return Padding(
                padding: const EdgeInsets.only(right: AppSpacing.xs),
                child: ActionChip(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: AppColors.gold.withValues(alpha: 0.12),
                  side: BorderSide(
                    color: AppColors.gold.withValues(alpha: 0.4),
                  ),
                  avatar: const Icon(
                    Icons.account_balance_wallet,
                    size: 16,
                    color: AppColors.gold,
                  ),
                  label: Text(
                    '\u20b9${bal.toStringAsFixed(0)}',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.gold,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onPressed: () => _showWalletSheet(context),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {},
          ),
        ],
      ),
      bottomNavigationBar: _FrostedGlassBottomNavBar(
        currentIndex: 0,
        onTap: (idx) {
          if (idx == 1) {
            try {
              context.push('/explore');
            } catch (_) {}
          } else if (idx == 2) {
            try {
              context.push('/orders');
            } catch (_) {}
          } else if (idx == 3) {
            try {
              context.push('/wallet');
            } catch (_) {}
          } else if (idx == 4) {
            try {
              context.push('/profile');
            } catch (_) {}
          }
        },
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(nearbyShopsProvider),
        child: CustomScrollView(
          cacheExtent: 2000,
          slivers: [
            // Top Welcome & Compact Glass Wallet Card
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                0,
              ),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'Namaste',
                          style: AppTypography.title.copyWith(fontSize: 18),
                        ),
                        if (isPinkie) ...[
                          const SizedBox(width: AppSpacing.xs),
                          const TwinkleSparkle(size: 14, color: AppColors.deepBlush),
                        ],
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.mint.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.bolt,
                                size: 12,
                                color: AppColors.success,
                              ),
                              SizedBox(width: 2),
                              Text(
                                '10-20 min delivery',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.success,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    // Compact Glass Wallet Header
                    _buildCompactWalletBar(context),
                  ],
                ),
              ),
            ),

            // Contextual Carousel (Reorder / Community / Ration)
            SliverPadding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              sliver: SliverToBoxAdapter(
                child: SizedBox(
                  height: 94,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                    ),
                    children: [
                      _buildReorderCard(context),
                      const SizedBox(width: AppSpacing.md),
                      _buildCommunityCard(context),
                      const SizedBox(width: AppSpacing.md),
                      _buildRationCard(context),
                    ],
                  ),
                ),
              ),
            ),

            // Search field
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xs,
                AppSpacing.lg,
                AppSpacing.xs,
              ),
              sliver: SliverToBoxAdapter(
                child: AppTextField(
                  label: '',
                  controller: _searchController,
                  hintText: 'Search shops, categories...',
                  prefixIcon: const Icon(Icons.search),
                  onChanged: (value) {
                    ref.read(shopSearchQueryProvider.notifier).state =
                        value.isEmpty ? null : value;
                  },
                ),
              ),
            ),

            // Category filter chips
            SliverToBoxAdapter(
              child: SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  children: [
                    // Favorite Toggle Chip
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.sm),
                      child: FilterChip(
                        avatar: Icon(
                          _onlyFavorites
                              ? Icons.favorite
                              : Icons.favorite_border,
                          size: 14,
                          color: _onlyFavorites
                              ? Colors.white
                              : (isPinkie ? AppColors.deepBlush : AppColors.gold),
                        ),
                        label: Text('My Shops (${favShopIds.length})'),
                        selected: _onlyFavorites,
                        selectedColor: isPinkie ? AppColors.deepBlush : AppColors.gold,
                        backgroundColor: (isPinkie ? AppColors.softPink : AppColors.sand).withValues(
                          alpha: 0.4,
                        ),
                        labelStyle: AppTypography.caption.copyWith(
                          color: _onlyFavorites
                              ? Colors.white
                              : (isPinkie ? AppColors.deepBlush : AppColors.gold),
                          fontWeight: FontWeight.bold,
                        ),
                        side: BorderSide(
                          color: (isPinkie ? AppColors.deepBlush : AppColors.gold).withValues(alpha: 0.3),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        onSelected: (val) {
                          setState(() => _onlyFavorites = val);
                        },
                      ),
                    ),
                    ..._categories.map((c) {
                      final isSelected =
                          !_onlyFavorites &&
                          ((_selectedCategory == null && c.$1 == 'All') ||
                              _selectedCategory == c.$1);
                      return Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.sm),
                        child: ChoiceChip(
                          avatar: Icon(
                            c.$2,
                            size: 14,
                            color: isSelected ? Colors.white : AppColors.ink,
                          ),
                          label: Text(c.$1),
                          selected: isSelected,
                          selectedColor: isPinkie ? AppColors.deepBlush : AppColors.gold,
                          side: BorderSide(
                            color: isSelected
                                ? (isPinkie ? AppColors.deepBlush : AppColors.gold)
                                : AppColors.ash.withValues(alpha: 0.2),
                          ),
                          labelStyle: AppTypography.caption.copyWith(
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isSelected ? Colors.white : AppColors.ink,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                          ),
                          onSelected: (selected) {
                            if (selected) {
                              setState(() {
                                _onlyFavorites = false;
                                _selectedCategory = c.$1 == 'All' ? null : c.$1;
                              });
                            }
                          },
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),

            // Shop list
            shopsAsync.when(
              loading: () => const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) =>
                  SliverFillRemaining(child: Center(child: Text('Error: $e'))),
              data: (shops) {
                var displayList = shops;
                if (_onlyFavorites) {
                  displayList = displayList
                      .where((s) => favShopIds.contains(s.id))
                      .toList();
                } else if (_selectedCategory != null) {
                  displayList = displayList
                      .where(
                        (s) => s.category.toLowerCase().contains(
                          _selectedCategory!.toLowerCase(),
                        ),
                      )
                      .toList();
                }

                if (displayList.isEmpty) {
                  return const SliverFillRemaining(
                    child: EmptyStateView(
                      icon: Icon(Icons.storefront_outlined),
                      title: 'No shops here yet',
                      subtitle:
                          'Check back soon \u2014 we\u2019re expanding fast.',
                    ),
                  );
                }
                final open = displayList.where((s) => s.isOpen).toList();
                final closed = displayList.where((s) => !s.isOpen).toList();
                return SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (open.isNotEmpty) ...[
                        _sectionHeader('Open now'),
                        ...open.map((s) => _ShopCard(shop: s)),
                      ],
                      if (closed.isNotEmpty) ...[
                        _sectionHeader('Currently closed'),
                        ...closed.map((s) => _ShopCard(shop: s, muted: true)),
                      ],
                    ],
                  ),
                );
              },
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 80)),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactWalletBar(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final walletAsync = ref.watch(walletDataProvider);
        final bal = walletAsync.valueOrNull?.balanceRupees ?? 0.0;

        return GestureDetector(
          onTap: () {
            try {
              context.push('/wallet');
            } catch (_) {
              _showWalletSheet(context);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.lavender.withValues(alpha: 0.35),
                  AppColors.blush.withValues(alpha: 0.3),
                ],
              ),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: AppColors.deepLavender.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                const CuteCoinBadge(size: 24),
                const SizedBox(width: AppSpacing.sm),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Paasel Balance',
                      style: AppTypography.caption.copyWith(
                        fontSize: 10,
                        color: AppColors.ash,
                      ),
                    ),
                    Text(
                      '\u20b9${bal.toStringAsFixed(2)}',
                      style: AppTypography.bodyStrong.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.mint.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: const Text(
                    '+5% cashback',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: AppColors.success,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, size: 16, color: AppColors.ash),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildReorderCard(BuildContext context) {
    return Container(
      width: 260,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.softPink.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.deepBlush.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
            child: const Icon(
              Icons.repeat_rounded,
              color: AppColors.deepBlush,
              size: 20,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '1-Tap Reorder',
                  style: AppTypography.caption.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.deepBlush,
                  ),
                ),
                Text(
                  'Your weekly grocery run',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption.copyWith(
                    fontSize: 10,
                    color: AppColors.ash,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.deepBlush,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              minimumSize: const Size(0, 30),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
            onPressed: () => triggerOneTapReorder(context: context, ref: ref),
            child: const Text(
              'Reorder',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommunityCard(BuildContext context) {
    return InkWell(
      onTap: () => context.push('/group-order'),
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        width: 250,
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.peach.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.warmPeach.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
              child: const Icon(
                Icons.groups_rounded,
                color: AppColors.warmPeach,
                size: 20,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Community Batch',
                    style: AppTypography.caption.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.warmPeach,
                    ),
                  ),
                  Text(
                    'Palm Heights Tower B • 🔒 Private Cart',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.caption.copyWith(
                      fontSize: 10,
                      color: AppColors.ash,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRationCard(BuildContext context) {
    return Container(
      width: 250,
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.lavender.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: AppColors.deepLavender.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
            child: const Icon(
              Icons.calendar_month_rounded,
              color: AppColors.deepLavender,
              size: 20,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Monthly Ration Kit',
                  style: AppTypography.caption.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.deepLavender,
                  ),
                ),
                Text(
                  'Atta, Oil & Spices on 1st',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption.copyWith(
                    fontSize: 10,
                    color: AppColors.ash,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.md,
      AppSpacing.lg,
      AppSpacing.xs,
    ),
    child: Text(title, style: AppTypography.label),
  );

  void _showAddressSheet() {
    AppBottomSheet.show<void>(
      context: context,
      builder: (_) => const _AddressSelector(),
    );
  }

  void _showWalletSheet(BuildContext context) {
    AppBottomSheet.show<void>(
      context: context,
      builder: (_) => const _WalletSheet(),
    );
  }
}

class _ShopCard extends ConsumerWidget {
  const _ShopCard({required this.shop, this.muted = false});
  final NearbyShop shop;
  final bool muted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final distanceKm = (shop.distanceM / 1000).toStringAsFixed(1);
    final isFav = ref.watch(favoriteShopsProvider).contains(shop.id);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: ScaleOnCard(
        onTap: () => context.push('/shop/${shop.id}'),
        child: Opacity(
          opacity: muted ? 0.55 : 1.0,
          child: Row(
            children: [
              // Storefront icon with pastel touch
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: (isFav && ref.watch(isPinkieThemeActiveProvider)
                      ? AppColors.softPink
                      : AppColors.sand).withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(
                    color: (ref.watch(isPinkieThemeActiveProvider)
                        ? AppColors.deepBlush
                        : AppColors.gold).withValues(alpha: 0.2),
                  ),
                ),
                child: Icon(
                  Icons.storefront_rounded,
                  color: ref.watch(isPinkieThemeActiveProvider)
                      ? AppColors.deepBlush
                      : AppColors.gold,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(shop.name, style: AppTypography.bodyMedium),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          shop.category,
                          style: AppTypography.caption.copyWith(
                            color: AppColors.ash,
                          ),
                        ),
                        if (shop.shopCode != null) ...[
                          const SizedBox(width: AppSpacing.xs),
                          Text(
                            '•',
                            style: AppTypography.caption.copyWith(
                              color: AppColors.ash,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.gold.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(
                                AppRadius.pill,
                              ),
                            ),
                            child: Text(
                              shop.shopCode!,
                              style: AppTypography.caption.copyWith(
                                color: AppColors.gold,
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$distanceKm km',
                    style: AppTypography.data.copyWith(color: AppColors.ash),
                  ),
                  const SizedBox(height: 4),
                  if (shop.isOpen)
                    const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GoldPulseIndicator(size: 6),
                        SizedBox(width: 4),
                        StatusBadge(status: StatusBadgeState.readyForPickup),
                      ],
                    ),
                ],
              ),
              TinyFloatingHeartButton(
                isFav: isFav,
                isEnabled: ref.watch(isPinkieThemeActiveProvider),
                onToggle: () {
                  ref
                      .read(favoriteShopsProvider.notifier)
                      .toggleFavorite(shop.id);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddressSelector extends ConsumerWidget {
  const _AddressSelector();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final addresses = ref.watch(addressListProvider);
    return addresses.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Text('Error: $e'),
      data: (list) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Deliver to', style: AppTypography.title),
          const SizedBox(height: AppSpacing.lg),
          ...list.map(
            (a) => ListTile(
              leading: const Icon(Icons.location_on_outlined),
              title: Text(a.label),
              subtitle: Text(
                a.addressText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () {
                ref.read(activeAddressProvider.notifier).state = a;
                Navigator.of(context).pop();
              },
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextActionButton(
            label: '+ Add new address',
            onPressed: () {
              Navigator.of(context).pop();
              context.go('/location-setup');
            },
          ),
        ],
      ),
    );
  }
}

class _WalletSheet extends ConsumerWidget {
  const _WalletSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final walletAsync = ref.watch(walletDataProvider);

    return walletAsync.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.xxl),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Text('Failed to load wallet: $e'),
      ),
      data: (wallet) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const CuteCoinBadge(size: 24),
                    const SizedBox(width: AppSpacing.sm),
                    Text('Paasel Wallet', style: AppTypography.title),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Text(
                    'Unified Account',
                    style: AppTypography.caption.copyWith(
                      color: AppColors.gold,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.paper.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.ash.withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Current Balance',
                    style: AppTypography.caption.copyWith(color: AppColors.ash),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '\u20b9${wallet.balanceRupees.toStringAsFixed(2)}',
                    style: AppTypography.price.copyWith(
                      color: AppColors.gold,
                      fontSize: 32,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Delivery earnings, refunds, and promo balances are unified here and spendable across any shop.',
                    style: AppTypography.caption.copyWith(color: AppColors.ash),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Transaction Ledger', style: AppTypography.bodyStrong),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    try {
                      context.push('/wallet');
                    } catch (_) {}
                  },
                  child: const Text(
                    'View Full Wallet',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (wallet.transactions.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                child: Center(
                  child: Text(
                    'No transactions yet.',
                    style: AppTypography.caption.copyWith(color: AppColors.ash),
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: wallet.transactions.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final tx = wallet.transactions[index];
                    final isCredit = tx.isCredit;
                    final prefix = isCredit ? '+' : '-';
                    final color = isCredit
                        ? AppColors.success
                        : AppColors.danger;

                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        radius: 16,
                        backgroundColor: color.withValues(alpha: 0.15),
                        child: Icon(
                          isCredit ? Icons.arrow_downward : Icons.arrow_upward,
                          size: 16,
                          color: color,
                        ),
                      ),
                      title: Text(
                        _txTitle(tx.type),
                        style: AppTypography.bodyMedium,
                      ),
                      subtitle: Text(
                        tx.description ?? tx.id,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.ash,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '$prefix\u20b9${tx.amountRupees.toStringAsFixed(2)}',
                            style: AppTypography.bodyStrong.copyWith(
                              color: color,
                            ),
                          ),
                          Text(
                            tx.status,
                            style: AppTypography.caption.copyWith(
                              fontSize: 10,
                              color: AppColors.ash,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  String _txTitle(String type) {
    switch (type.toLowerCase()) {
      case 'rider_earning':
        return 'Delivery Earning';
      case 'order_wallet_payment':
        return 'Order Payment';
      case 'order_refund':
        return 'Order Refund';
      case 'admin_adjustment':
        return 'Admin Adjustment';
      case 'transaction_reversal':
        return 'Reversal';
      default:
        return type.replaceAll('_', ' ').toUpperCase();
    }
  }
}

/// Floating frosted-glass bottom navigation bar with Apple-like pill styling.
class _FrostedGlassBottomNavBar extends StatelessWidget {
  const _FrostedGlassBottomNavBar({
    required this.currentIndex,
    required this.onTap,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final navItems = const [
      (Icons.home_rounded, 'Home'),
      (Icons.explore_rounded, 'Explore'),
      (Icons.receipt_long_rounded, 'Orders'),
      (Icons.account_balance_wallet_rounded, 'Wallet'),
      (Icons.person_rounded, 'Profile'),
    ];

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.sm,
        ),
        height: 62,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: AppGlassCard(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          backgroundColor: Colors.white.withValues(alpha: 0.88),
          borderColor: Colors.black.withValues(alpha: 0.07),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(navItems.length, (idx) {
              final isSelected = currentIndex == idx;
              final item = navItems[idx];

              return InkWell(
                onTap: () => onTap(idx),
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: EdgeInsets.symmetric(
                    horizontal: isSelected ? AppSpacing.md : AppSpacing.sm,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.gold.withValues(alpha: 0.15)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        item.$1,
                        size: 20,
                        color: isSelected ? AppColors.gold : AppColors.ash,
                      ),
                      if (isSelected) ...[
                        const SizedBox(width: 4),
                        Text(
                          item.$2,
                          style: AppTypography.caption.copyWith(
                            color: AppColors.gold,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
